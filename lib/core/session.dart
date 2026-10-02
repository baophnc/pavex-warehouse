import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../data/models.dart';
import '../data/repository.dart';
import 'api.dart';
import 'trip_tracker.dart';

/// What the signed-in person does in the field; decides which tabs they get.
enum WorkRole {
  courier('Bưu tá'),
  hubManager('Trưởng bưu cục'),
  hubStaff('Nhân viên bưu cục'),
  driver('Tài xế trung chuyển'),
  unsupported('Tài khoản khác');

  const WorkRole(this.label);

  final String label;

  bool get worksAtHub => this == hubManager || this == hubStaff;
  bool get handlesCash => this == courier || worksAtHub;
}

class SessionUser {
  SessionUser({required this.userId, required this.email, required this.roles, required this.permissions});

  /// Reads the claims of a Pavex access token (signature is checked by the server).
  factory SessionUser.fromToken(String token) {
    final parts = token.split('.');
    if (parts.length != 3) throw const FormatException('Access token is malformed');
    final payload = jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(parts[1])))) as Map<String, dynamic>;
    Set<String> strings(dynamic value) => value is List ? value.map((item) => '$item').toSet() : <String>{};
    return SessionUser(
      userId: '${payload['sub']}',
      email: '${payload['email'] ?? ''}',
      roles: strings(payload['roles']),
      permissions: strings(payload['permissions']),
    );
  }

  final String userId;
  final String email;
  final Set<String> roles;
  final Set<String> permissions;

  bool can(String permission) => permissions.contains(permission);

  WorkRole get role {
    if (roles.contains('HUB_MANAGER')) return WorkRole.hubManager;
    if (roles.contains('WAREHOUSE_OPERATOR')) return WorkRole.hubStaff;
    if (roles.contains('COURIER')) return WorkRole.courier;
    if (roles.contains('LINE_HAUL_DRIVER')) return WorkRole.driver;
    return WorkRole.unsupported;
  }
}

/// Holds the tokens (in the device keychain), the signed-in worker and their hubs.
class SessionController extends ChangeNotifier implements TokenProvider {
  SessionController(this.repository, {FlutterSecureStorage? storage}) : _storage = storage ?? _defaultStorage {
    repository.api.tokens = this;
  }

  /// On macOS the data protection keychain needs a signing team and a keychain-access-groups
  /// entitlement; a locally signed debug build has neither, so use the login keychain there.
  static const _defaultStorage = FlutterSecureStorage(
    mOptions: MacOsOptions(usesDataProtectionKeychain: false),
  );

  static const _accessKey = 'pavex.accessToken';
  static const _refreshKey = 'pavex.refreshToken';
  static const _passwordChangeKey = 'pavex.passwordChangeRequired';

  final PavexRepository repository;
  final FlutterSecureStorage _storage;

  /// GPS recording of the line-haul trip in progress (drivers only).
  late final TripTracker trips = TripTracker(repository);

  String? _accessToken;
  String? _refreshToken;
  Future<bool>? _refreshing;

  SessionUser? user;
  Profile? profile;

  /// Signed in with the temporary password: the app asks for a new one before anything else.
  bool passwordChangeRequired = false;
  HubScope? hubScope;

  /// The hub the worker is standing in; hub screens and scans use it.
  MyHub? currentHub;

  bool get signedIn => user != null;

  @override
  String? get accessToken => _accessToken;

  Future<void> restore() async {
    _accessToken = await _storage.read(key: _accessKey);
    _refreshToken = await _storage.read(key: _refreshKey);
    passwordChangeRequired = await _storage.read(key: _passwordChangeKey) == 'true';
    if (_accessToken == null || _refreshToken == null) return;
    try {
      user = SessionUser.fromToken(_accessToken!);
      await _loadWorker();
    } catch (_) {
      await _clear();
    }
    notifyListeners();
  }

  Future<void> login(String email, String password) async {
    final tokens = await repository.login(email, password);
    await _store(tokens);
    try {
      await _loadWorker();
    } catch (_) {
      await _clear();
      rethrow;
    }
    notifyListeners();
  }

  Future<void> logout() async {
    final refresh = _refreshToken;
    if (refresh != null) {
      try {
        await repository.logout(refresh);
      } catch (_) {
        // Signing out locally still protects the device.
      }
    }
    await _clear();
    notifyListeners();
  }

  /// Replaces the temporary password, then signs in again: changing it ends every session.
  Future<void> changePassword(String currentPassword, String newPassword) async {
    final email = user?.email;
    await repository.changePassword(currentPassword, newPassword);
    await _clear();
    if (email != null && email.isNotEmpty) {
      await login(email, newPassword);
    } else {
      notifyListeners();
    }
  }

  void selectHub(MyHub hub) {
    currentHub = hub;
    notifyListeners();
  }

  /// Several requests may hit an expired token at once; they share one refresh.
  @override
  Future<bool> refresh() {
    final pending = _refreshing;
    if (pending != null) return pending;
    final future = _refresh().whenComplete(() => _refreshing = null);
    _refreshing = future;
    return future;
  }

  Future<bool> _refresh() async {
    final token = _refreshToken;
    if (token == null) return false;
    try {
      await _store(await repository.refresh(token));
      return true;
    } on ApiException catch (error) {
      if (error.status == 400 || error.status == 401) {
        await _clear();
        notifyListeners();
      }
      return false;
    }
  }

  Future<void> _loadWorker() async {
    final results = await Future.wait([repository.me(), repository.hubScope()]);
    profile = results[0] as Profile;
    hubScope = results[1] as HubScope;
    currentHub = hubScope!.primary;
    if (user?.role == WorkRole.driver) unawaited(resumeRunningTrip());
  }

  /// A driver who reopens the app mid-trip keeps sending positions without opening the trips tab.
  Future<void> resumeRunningTrip() async {
    try {
      if ((await repository.fleetConsent()).required) return;
      final running = (await repository.myTrips()).where((trip) => trip.inProgress && trip.tripId != null).firstOrNull;
      if (running != null) await trips.resume(running.tripId!);
    } catch (_) {
      // The trips tab retries when it loads.
    }
  }

  Future<void> _store(AuthTokens tokens) async {
    _accessToken = tokens.accessToken;
    _refreshToken = tokens.refreshToken;
    user = SessionUser.fromToken(tokens.accessToken);
    passwordChangeRequired = tokens.passwordChangeRequired;
    await _storage.write(key: _accessKey, value: tokens.accessToken);
    await _storage.write(key: _refreshKey, value: tokens.refreshToken);
    await _storage.write(key: _passwordChangeKey, value: '${tokens.passwordChangeRequired}');
  }

  Future<void> _clear() async {
    await trips.stop();
    _accessToken = null;
    _refreshToken = null;
    user = null;
    profile = null;
    hubScope = null;
    currentHub = null;
    passwordChangeRequired = false;
    await _storage.delete(key: _passwordChangeKey);
    await _storage.delete(key: _accessKey);
    await _storage.delete(key: _refreshKey);
  }
}
