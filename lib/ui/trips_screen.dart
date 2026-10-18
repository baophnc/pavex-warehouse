import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../app.dart';
import '../core/api.dart';
import '../core/format.dart';
import '../core/trip_tracker.dart';
import '../data/models.dart';
import 'theme.dart';
import 'widgets.dart';

/// Server error codes of the trip APIs, in the driver's words.
String tripErrorText(Object error) {
  if (error is ApiException) {
    switch (error.code) {
      case 'consent_required':
        return 'Bạn cần đồng ý chia sẻ vị trí ở tab Chuyến thì app mới gửi được vị trí xe.';
      case 'another_trip_in_progress':
        return 'Bạn đang có chuyến khác chưa kết thúc. Bấm “Đã tới” cho chuyến đó trước.';
      case 'trip_not_assigned':
        return 'Chuyến này không còn trong việc được giao của bạn.';
      case 'trip_already_arrived':
        return 'Chuyến này đã kết thúc.';
      case 'vehicle_plate_invalid':
        return 'Biển số chỉ gồm chữ, số, dấu chấm và gạch ngang (ví dụ 29C-123.45).';
      case 'terms_outdated':
        return 'Điều khoản vừa được cập nhật. Tải lại rồi đồng ý lần nữa.';
    }
  }
  return errorText(error);
}

/// A line-haul driver's departures today: start a trip, see that GPS is being sent, mark arrival.
class TripsScreen extends StatefulWidget {
  const TripsScreen({super.key});

  @override
  State<TripsScreen> createState() => _TripsScreenState();
}

class _TripsScreenState extends State<TripsScreen> {
  late Future<(FleetConsent, List<DriverTrip>)> _data;
  String? _busy;

  @override
  void initState() {
    super.initState();
    _data = _load();
  }

  Future<(FleetConsent, List<DriverTrip>)> _load() async {
    final session = AppScope.read(context);
    final results = await Future.wait([session.repository.fleetConsent(), session.repository.myTrips()]);
    final consent = results[0] as FleetConsent;
    final trips = results[1] as List<DriverTrip>;
    // Recording survives app restarts: resume it for the trip the server still has running, but
    // only once the driver agreed to share the truck's position.
    final running = trips.where((trip) => trip.inProgress && trip.tripId != null).firstOrNull;
    if (running != null && !consent.required) {
      await session.trips.resume(running.tripId!);
    } else if (session.trips.active) {
      await session.trips.stop();
    }
    return (consent, trips);
  }

  Future<void> _refresh() async {
    final next = _load();
    setState(() => _data = next);
    await next;
  }

  Future<void> _run(String key, Future<void> Function() action, String done) async {
    setState(() => _busy = key);
    try {
      await action();
      if (mounted) showMessage(context, done);
      await _refresh();
    } catch (error) {
      if (mounted) showMessage(context, tripErrorText(error), error: true);
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  Future<void> _accept(FleetConsent consent) => _run(
        'consent',
        () => AppScope.repository(context).acceptFleetConsent(consent.currentTermsVersion),
        'Đã lưu. Bạn có thể bắt đầu chuyến.',
      );

  Future<void> _start(DriverTrip trip) async {
    final controller = TextEditingController();
    final plate = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Bắt đầu chuyến ${trip.fromHubCode} → ${trip.toHubCode}?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('App sẽ gửi vị trí xe cho tới khi chuyến kết thúc.'),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              textCapitalization: TextCapitalization.characters,
              maxLength: 20,
              decoration: const InputDecoration(labelText: 'Biển số xe (không bắt buộc)', hintText: '29C-123.45'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Hủy')),
          FilledButton(onPressed: () => Navigator.pop(context, controller.text.trim()), child: const Text('Bắt đầu')),
        ],
      ),
    );
    controller.dispose();
    if (plate == null || !mounted) return;
    final session = AppScope.read(context);
    await _run(trip.laneId + trip.plannedDepartureRaw, () async {
      final started = await session.repository.startTrip(trip, vehiclePlate: plate.isEmpty ? null : plate);
      if (started.tripId != null) await session.trips.resume(started.tripId!);
    }, 'Đã bắt đầu chuyến. Đang gửi vị trí xe.');
  }

  Future<void> _arrive(DriverTrip trip) async {
    final ok = await confirm(
      context,
      title: 'Xe đã tới ${trip.toHubName}?',
      message: 'App sẽ ngừng gửi vị trí. Nếu hub đến nhập đủ kiện, chuyến cũng tự kết thúc.',
      action: 'Đã tới',
    );
    if (!ok || !mounted) return;
    final session = AppScope.read(context);
    await _run(trip.tripId!, () async {
      await session.trips.flush();
      await session.repository.arriveTrip(trip.tripId!);
      await session.trips.stop();
    }, 'Đã kết thúc chuyến.');
  }

  @override
  Widget build(BuildContext context) {
    final tracker = AppScope.read(context).trips;
    return Scaffold(
      appBar: AppBar(title: const Text('Chuyến xe')),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: FutureBuilder(
          future: _data,
          builder: (context, snapshot) {
            if (snapshot.hasError) return ListView(children: [ErrorPanel(error: snapshot.error!, onRetry: _refresh)]);
            if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
            final (consent, trips) = snapshot.data!;
            final current = trips.where((trip) => !trip.arrived).toList();
            final done = trips.where((trip) => trip.arrived).toList();
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              children: [
                if (consent.required) _ConsentCard(busy: _busy == 'consent', onAccept: () => _accept(consent)),
                ListenableBuilder(listenable: tracker, builder: (context, _) => _TrackerBanner(tracker: tracker)),
                SectionTitle('Chuyến hôm nay (${current.length})'),
                if (current.isEmpty)
                  const EmptyState(
                    icon: Icons.local_shipping_outlined,
                    title: 'Chưa có chuyến nào',
                    message: 'Khi bạn được giao việc trung chuyển, chuyến xe sẽ hiện ở đây.',
                  ),
                for (final trip in current)
                  _TripCard(
                    trip: trip,
                    busy: _busy == (trip.tripId ?? trip.laneId + trip.plannedDepartureRaw),
                    canStart: !consent.required && !trips.any((other) => other.inProgress),
                    onStart: () => _start(trip),
                    onArrive: () => _arrive(trip),
                  ),
                if (done.isNotEmpty) ...[
                  const SectionTitle('Đã tới trong 24 giờ qua'),
                  for (final trip in done) _TripCard(trip: trip, busy: false, canStart: false, onStart: () {}, onArrive: () {}),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}

class _ConsentCard extends StatelessWidget {
  const _ConsentCard({required this.busy, required this.onAccept});

  final bool busy;
  final VoidCallback onAccept;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Chia sẻ vị trí khi chạy chuyến', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              const Text(
                '• App chỉ ghi vị trí trong lúc chuyến trung chuyển đang chạy, và tự dừng khi xe tới nơi.\n'
                '• Chỉ trưởng bưu cục nơi xe đi, nơi xe đến và bộ phận vận hành xem được. Khách hàng không xem được.\n'
                '• Dữ liệu vị trí được lưu 30 ngày rồi tự xoá. Mỗi lần có người mở lộ trình đều được ghi lại.',
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: busy ? null : onAccept,
                icon: busy ? const SizedBox.square(dimension: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.check),
                label: const Text('Tôi đồng ý'),
              ),
            ],
          ),
        ),
      );
}

class _TrackerBanner extends StatelessWidget {
  const _TrackerBanner({required this.tracker});

  final TripTracker tracker;

  @override
  Widget build(BuildContext context) {
    if (!tracker.active) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    if (tracker.problem != TrackingProblem.none) {
      // A browser has no settings screen to open; the site permission is in the address bar.
      final message = kIsWeb
          ? 'Trình duyệt chưa cho phép vị trí (cần cho phép vị trí cho trang này, và trang phải mở qua https:// '
              'hoặc localhost). Chạy chuyến thật hãy dùng app trên điện thoại.'
          : switch (tracker.problem) {
              TrackingProblem.serviceOff => 'Định vị của điện thoại đang tắt. Bật lên để gửi vị trí xe.',
              TrackingProblem.deniedForever => 'App chưa được phép dùng vị trí. Mở Cài đặt và cho phép vị trí.',
              _ => 'App chưa được phép dùng vị trí. Cho phép để gửi vị trí xe.',
            };
      return Card(
        color: scheme.errorContainer,
        child: ListTile(
          leading: Icon(Icons.location_off, color: scheme.onErrorContainer),
          title: Text(message, style: TextStyle(color: scheme.onErrorContainer)),
          trailing: kIsWeb ? null : TextButton(onPressed: tracker.openSettings, child: const Text('Cài đặt')),
        ),
      );
    }
    return Card(
      child: ListTile(
        leading: const Icon(Icons.gps_fixed, color: successGreen),
        title: const Text('Đang gửi vị trí xe'),
        subtitle: Text(
          'Gửi lần cuối: ${tracker.lastSentAt == null ? 'chưa' : timeOf(tracker.lastSentAt)}'
          '${tracker.pending > 0 ? ' · ${tracker.pending} điểm chờ gửi' : ''}'
          '${kIsWeb ? '\nBản web chỉ gửi vị trí khi tab này đang mở; đóng tab hoặc khoá máy là dừng gửi.' : ''}',
        ),
      ),
    );
  }
}

class _TripCard extends StatelessWidget {
  const _TripCard({
    required this.trip,
    required this.busy,
    required this.canStart,
    required this.onStart,
    required this.onArrive,
  });

  final DriverTrip trip;
  final bool busy;
  final bool canStart;
  final VoidCallback onStart;
  final VoidCallback onArrive;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (trip.status) {
      'IN_PROGRESS' => ('Đang chạy', Theme.of(context).colorScheme.primary),
      'ARRIVED' => ('Đã tới', successGreen),
      _ => ('Chờ chạy', warningAmber),
    };
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text('${trip.fromHubCode} → ${trip.toHubCode}', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                ),
                StatusChip(label, color: color),
              ],
            ),
            const SizedBox(height: 4),
            Text('${trip.fromHubName} → ${trip.toHubName}'),
            const SizedBox(height: 8),
            Text(
              'Kế hoạch: ${dayTime(trip.plannedDepartureAt)} → ${timeOf(trip.plannedArrivalAt)}'
              '${trip.distanceKm == null ? '' : ' · ${trip.distanceKm!.toStringAsFixed(0)} km'}',
            ),
            if (trip.shipmentCount > 0) Text('${trip.shipmentCount} vận đơn trên chuyến'),
            if (trip.startedAt != null)
              Text('Bắt đầu: ${timeOf(trip.startedAt)}${trip.vehiclePlate == null ? '' : ' · Xe ${trip.vehiclePlate}'}'),
            if (trip.arrivedAt != null) Text('Tới lúc: ${timeOf(trip.arrivedAt)}'),
            if (trip.planned || trip.inProgress) ...[
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: trip.inProgress
                    ? FilledButton.icon(
                        onPressed: busy ? null : onArrive,
                        icon: const Icon(Icons.flag),
                        label: const Text('Đã tới nơi'),
                      )
                    : OutlinedButton.icon(
                        onPressed: busy || !canStart ? null : onStart,
                        icon: const Icon(Icons.play_arrow),
                        label: const Text('Bắt đầu chuyến'),
                      ),
              ),
              if (trip.planned)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    'Chuyến cũng tự bắt đầu khi bạn quét kiện đầu tiên lên xe.',
                    style: TextStyle(color: Theme.of(context).colorScheme.outline, fontSize: 12),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}
