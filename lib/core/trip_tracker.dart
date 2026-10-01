import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/repository.dart';
import 'api.dart';

/// Why the tracker cannot record positions right now.
enum TrackingProblem { none, serviceOff, denied, deniedForever }

/// Records the truck's GPS while a line-haul trip is in progress and sends it in batches.
///
/// Points are kept on the phone until the server confirms them, so a dead zone on the highway
/// only delays them. Each point carries its own sequence number; the server ignores resends.
class TripTracker extends ChangeNotifier {
  TripTracker(this._repository);

  final PavexRepository _repository;

  static const _seqKey = 'pavex.fleet.seq';
  static const _bufferKey = 'pavex.fleet.buffer';
  static const _tripKey = 'pavex.fleet.trip';
  static const _flushEvery = Duration(seconds: 30);
  static const _heartbeatAfter = Duration(seconds: 60);
  static const _batchSize = 200;
  static const _maxBuffered = 5000;

  StreamSubscription<Position>? _positions;
  Timer? _timer;
  List<Map<String, dynamic>> _buffer = [];
  bool _sending = false;
  int _seq = 0;
  DateTime? _lastFixAt;

  /// The trip whose positions are being recorded, or null.
  String? tripId;
  DateTime? lastSentAt;
  TrackingProblem problem = TrackingProblem.none;

  bool get active => tripId != null;
  int get pending => _buffer.length;

  /// Starts (or keeps) recording for [id]. Safe to call again, e.g. whenever the trip list loads.
  Future<void> resume(String id) async {
    if (tripId == id && _positions != null) return;
    await stop(keepBuffer: tripId == id);
    final prefs = await SharedPreferences.getInstance();
    _seq = prefs.getInt(_seqKey) ?? 0;
    if (prefs.getString(_tripKey) == id) {
      _buffer = (jsonDecode(prefs.getString(_bufferKey) ?? '[]') as List).cast<Map>().map((p) => p.cast<String, dynamic>()).toList();
    }
    tripId = id;
    await prefs.setString(_tripKey, id);
    if (!await _ensurePermission()) {
      notifyListeners();
      return;
    }
    _positions = Geolocator.getPositionStream(locationSettings: _settings()).listen(_record, onError: (_) {});
    _timer = Timer.periodic(_flushEvery, (_) => _tick());
    notifyListeners();
  }

  /// Stops recording. Unsent points are dropped unless [keepBuffer] is set.
  Future<void> stop({bool keepBuffer = false}) async {
    await _positions?.cancel();
    _positions = null;
    _timer?.cancel();
    _timer = null;
    if (!keepBuffer) {
      tripId = null;
      _buffer = [];
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_bufferKey);
      await prefs.remove(_tripKey);
    }
    notifyListeners();
  }

  /// Sends what is buffered now; used before the driver presses "Arrived".
  Future<void> flush() async {
    final id = tripId;
    if (id == null || _sending || _buffer.isEmpty) return;
    _sending = true;
    try {
      while (_buffer.isNotEmpty && tripId == id) {
        final batch = _buffer.take(_batchSize).toList();
        final result = await _repository.sendLocations(id, batch);
        _buffer.removeRange(0, batch.length);
        await _persist();
        lastSentAt = DateTime.now();
        if (result.tripStatus != 'IN_PROGRESS') {
          // The trip ended on the server (driver or destination hub): stop sending.
          await stop();
          return;
        }
      }
    } on ApiException catch (error) {
      if (error.status == 404) {
        await stop();
      } else if (error.status == 400) {
        // A batch the server will never accept must not block the ones behind it.
        _buffer.removeRange(0, _buffer.length < _batchSize ? _buffer.length : _batchSize);
        await _persist();
      }
      // Network errors and 5xx: keep the points and retry on the next tick.
    } finally {
      _sending = false;
      notifyListeners();
    }
  }

  Future<bool> _ensurePermission() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      problem = TrackingProblem.serviceOff;
      return false;
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) permission = await Geolocator.requestPermission();
    problem = switch (permission) {
      LocationPermission.deniedForever => TrackingProblem.deniedForever,
      LocationPermission.denied || LocationPermission.unableToDetermine => TrackingProblem.denied,
      _ => TrackingProblem.none,
    };
    return problem == TrackingProblem.none;
  }

  /// Opens the system settings when the driver has to allow location there.
  Future<void> openSettings() async {
    if (problem == TrackingProblem.serviceOff) {
      await Geolocator.openLocationSettings();
    } else {
      await Geolocator.openAppSettings();
    }
  }

  LocationSettings _settings() {
    if (defaultTargetPlatform == TargetPlatform.android) {
      return AndroidSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 30,
        intervalDuration: const Duration(seconds: 15),
        foregroundNotificationConfig: const ForegroundNotificationConfig(
          notificationTitle: 'Pavex đang ghi vị trí chuyến xe',
          notificationText: 'Chỉ ghi trong lúc chuyến đang chạy. Tự dừng khi xe tới nơi.',
          enableWakeLock: true,
          setOngoing: true,
        ),
      );
    }
    if (defaultTargetPlatform == TargetPlatform.iOS || defaultTargetPlatform == TargetPlatform.macOS) {
      return AppleSettings(
        accuracy: LocationAccuracy.high,
        activityType: ActivityType.automotiveNavigation,
        distanceFilter: 30,
        pauseLocationUpdatesAutomatically: false,
        showBackgroundLocationIndicator: true,
        allowBackgroundLocationUpdates: true,
      );
    }
    return const LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: 30);
  }

  void _record(Position position) {
    _seq += 1;
    _lastFixAt = DateTime.now();
    _buffer.add({
      'seq': _seq,
      'recordedAt': position.timestamp.toUtc().toIso8601String(),
      'lat': position.latitude,
      'lng': position.longitude,
      'accuracyM': position.accuracy.clamp(0, 10000),
      'speedMps': position.speed >= 0 ? position.speed.clamp(0, 100) : null,
      'headingDeg': position.heading >= 0 ? position.heading.clamp(0, 360) : null,
      'mocked': position.isMocked,
    });
    if (_buffer.length > _maxBuffered) _buffer.removeRange(0, _buffer.length - _maxBuffered);
    unawaited(_persist());
    notifyListeners();
  }

  /// Sends the buffer, and when the truck stands still asks for one fix so it does not look lost.
  Future<void> _tick() async {
    final last = _lastFixAt;
    if (last == null || DateTime.now().difference(last) >= _heartbeatAfter) {
      try {
        _record(await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(accuracy: LocationAccuracy.medium, timeLimit: Duration(seconds: 10)),
        ));
      } catch (_) {
        // No fix right now; the server shows "signal lost" after a while, which is true.
      }
    }
    await flush();
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_seqKey, _seq);
    await prefs.setString(_bufferKey, jsonEncode(_buffer));
  }

  @override
  void dispose() {
    _positions?.cancel();
    _timer?.cancel();
    super.dispose();
  }
}
