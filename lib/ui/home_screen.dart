import 'package:flutter/material.dart';

import '../app.dart';
import '../core/format.dart';
import '../core/session.dart';
import '../data/models.dart';
import '../data/repository.dart';
import 'account_screen.dart';
import 'shell.dart';
import 'theme.dart';
import 'widgets.dart';

/// The start of a shift: check in, go available, and see what is waiting.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.onOpenTab});

  final void Function(ShellTab tab) onOpenTab;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late Future<_HomeData> _data;
  bool _busy = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _data = _load();
  }

  Future<_HomeData> _load() async {
    final session = AppScope.session(context);
    final repository = session.repository;
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day);
    final role = session.user!.role;

    // One section failing (e.g. no shift configured) must not blank the whole screen.
    final shifts = repository
        .shifts(start.subtract(const Duration(hours: 6)), start.add(const Duration(days: 1, hours: 6)))
        .catchError((_) => const <MyShift>[]);
    final availability = repository.availability().then<Availability?>((value) => value).catchError((_) => null);
    final tasks = repository.tasks().catchError((_) => const <WorkTask>[]);
    final held = role == WorkRole.courier
        ? repository.myCollections(status: 'HELD').catchError((_) => const <CashCollection>[])
        : Future.value(const <CashCollection>[]);
    // Only the worker's own numbers: hub totals belong to the management portal.
    final summary = repository.reportSummary(DateRange.today()).catchError((_) => ReportSummary.empty);

    return _HomeData(
      shifts: await shifts,
      availability: await availability,
      tasks: await tasks,
      held: await held,
      summary: await summary,
    );
  }

  Future<void> _refresh() async {
    final next = _load();
    setState(() => _data = next);
    await next;
  }

  /// Runs one action and reports only its own outcome; reloading the screen afterwards is separate,
  /// so a section that fails to reload never turns a done check-in into an error message.
  Future<void> _run(Future<void> Function() action, String done) async {
    setState(() => _busy = true);
    try {
      await action();
      if (mounted) showMessage(context, done);
    } catch (error) {
      if (mounted) showMessage(context, errorText(error), error: true);
    }
    if (!mounted) return;
    setState(() => _busy = false);
    await _refresh().catchError((_) {});
  }

  @override
  Widget build(BuildContext context) {
    final session = AppScope.session(context);
    final repository = session.repository;
    final role = session.user!.role;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Hôm nay'),
        actions: [
          IconButton(
            tooltip: 'Tài khoản',
            icon: const Icon(Icons.account_circle_outlined),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AccountScreen())),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: FutureBuilder<_HomeData>(
          future: _data,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return ListView(children: [ErrorPanel(error: snapshot.error!, onRetry: _refresh)]);
            }
            final data = snapshot.data;
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              children: [
                _Greeting(session: session),
                if (data == null)
                  const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator()))
                else ...[
                  const SectionTitle('Ca làm việc'),
                  if (data.shifts.isEmpty)
                    const Card(child: ListTile(leading: Icon(Icons.event_busy), title: Text('Hôm nay bạn chưa được xếp ca.')))
                  else
                    for (final shift in data.shifts)
                      Card(
                        child: ListTile(
                          leading: const Icon(Icons.schedule),
                          title: Text(shift.name),
                          subtitle: Text('${timeOf(shift.startsAt)} – ${timeOf(shift.endsAt)} · ${shift.hubName ?? ''}'),
                          trailing: _shiftAction(shift, repository),
                        ),
                      ),
                  if (data.availability != null) ...[
                    const SizedBox(height: 10),
                    Card(
                      child: SwitchListTile(
                        value: data.availability!.available,
                        onChanged: _busy
                            ? null
                            : (value) => _run(
                                  () => repository.setAvailability(value),
                                  value ? 'Bạn sẽ được giao việc mới khi đang trong ca.' : 'Tạm ngưng nhận việc mới.',
                                ),
                        title: const Text('Sẵn sàng nhận việc', style: TextStyle(fontWeight: FontWeight.w700)),
                        subtitle: Text(
                          'Đang làm ${data.availability!.activeAssignments}/${data.availability!.maxConcurrentAssignments} việc. '
                          'Phải vào ca mới được tự động giao việc.',
                        ),
                      ),
                    ),
                  ],
                  const SectionTitle('Việc đang chờ'),
                  _TaskCounters(tasks: data.tasks, onOpen: () => widget.onOpenTab(ShellTab.tasks)),
                  if (role == WorkRole.courier) ...[
                    const SectionTitle('Tiền đang giữ'),
                    Card(
                      child: ListTile(
                        leading: const Icon(Icons.account_balance_wallet_outlined, color: warningAmber),
                        title: Text(
                          money(data.held.fold<int>(0, (sum, item) => sum + item.amount)),
                          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
                        ),
                        subtitle: Text('${data.held.length} đơn chưa nộp về bưu cục'),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => widget.onOpenTab(ShellTab.cash),
                      ),
                    ),
                  ],
                  SectionTitle(
                    'Kết quả của bạn hôm nay',
                    trailing: TextButton(onPressed: () => widget.onOpenTab(ShellTab.reports), child: const Text('Báo cáo')),
                  ),
                  _TodayNumbers(summary: data.summary, role: role),
                ],
                const SectionTitle('Thao tác nhanh'),
                FilledButton.icon(
                  onPressed: () => widget.onOpenTab(ShellTab.scan),
                  icon: const Icon(Icons.qr_code_scanner),
                  label: const Text('Quét mã vận đơn'),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

extension on _HomeScreenState {
  /// Check in only while the server accepts it; outside that window say when it opens.
  Widget _shiftAction(MyShift shift, PavexRepository repository) {
    final now = DateTime.now();
    if (shift.canCheckOut) {
      return OutlinedButton(
        onPressed: _busy ? null : () => _run(() => repository.checkOut(shift.shiftId), 'Đã ra ca.'),
        child: const Text('Ra ca'),
      );
    }
    if (shift.checkInOpen(now)) {
      return FilledButton(
        onPressed: _busy ? null : () => _run(() => repository.checkIn(shift.shiftId), 'Đã vào ca. Bạn đang sẵn sàng nhận việc.'),
        child: const Text('Vào ca'),
      );
    }
    final muted = TextStyle(color: Theme.of(context).colorScheme.outline, fontSize: 12);
    if (shift.checkedOutAt != null) return Text('Đã ra ca', style: muted);
    if (shift.ended(now)) return Text('Đã hết ca', style: muted);
    return Text('Vào ca từ ${timeOf(shift.checkInOpensAt)}', style: muted);
  }
}

class _HomeData {
  _HomeData({required this.shifts, required this.availability, required this.tasks, required this.held, required this.summary});

  final List<MyShift> shifts;
  final Availability? availability;
  final List<WorkTask> tasks;
  final List<CashCollection> held;
  final ReportSummary summary;
}

class _Greeting extends StatelessWidget {
  const _Greeting({required this.session});

  final SessionController session;

  @override
  Widget build(BuildContext context) {
    final hubs = session.hubScope?.hubs ?? const <MyHub>[];
    final current = session.currentHub;
    return Card(
      color: Theme.of(context).colorScheme.primary,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Xin chào, ${session.profile?.name ?? session.user!.email}',
              style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 4),
            Text(session.user!.role.label, style: const TextStyle(color: Colors.white70)),
            const SizedBox(height: 12),
            InkWell(
              onTap: hubs.length < 2 ? null : () => _pickHub(context, hubs),
              child: Row(
                children: [
                  const Icon(Icons.store_mall_directory_outlined, color: Colors.white, size: 18),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      current?.name ?? 'Chưa được phân bưu cục',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                    ),
                  ),
                  if (hubs.length > 1) const Icon(Icons.swap_horiz, color: Colors.white),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickHub(BuildContext context, List<MyHub> hubs) async {
    final hub = await showModalBottomSheet<MyHub>(
      context: context,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const ListTile(title: Text('Chọn bưu cục đang làm việc', style: TextStyle(fontWeight: FontWeight.w800))),
            for (final hub in hubs)
              ListTile(
                leading: Icon(hub.id == session.currentHub?.id ? Icons.radio_button_checked : Icons.radio_button_off),
                title: Text(hub.name),
                subtitle: Text(hub.code),
                onTap: () => Navigator.pop(context, hub),
              ),
          ],
        ),
      ),
    );
    if (hub != null) session.selectHub(hub);
  }
}

class _TaskCounters extends StatelessWidget {
  const _TaskCounters({required this.tasks, required this.onOpen});

  final List<WorkTask> tasks;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    int count(bool Function(WorkTask) test) => tasks.where(test).length;
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      childAspectRatio: 1.6,
      children: [
        MetricTile(label: 'Việc mới được giao', value: '${count((task) => task.awaitingAcceptance)}', icon: Icons.fiber_new_outlined, color: warningAmber, onTap: onOpen),
        MetricTile(label: 'Đang làm', value: '${count((task) => task.inProgress || task.awaitingStart)}', icon: Icons.pending_actions, onTap: onOpen),
        MetricTile(label: 'Lấy hàng', value: '${count((task) => task.isPickup)}', icon: Icons.move_to_inbox_outlined, onTap: onOpen),
        MetricTile(label: 'Giao hàng', value: '${count((task) => task.isDelivery)}', icon: Icons.local_shipping_outlined, onTap: onOpen),
      ],
    );
  }
}

class _TodayNumbers extends StatelessWidget {
  const _TodayNumbers({required this.summary, required this.role});

  final ReportSummary summary;
  final WorkRole role;

  @override
  Widget build(BuildContext context) {
    final tiles = <MetricTile>[
      if (role == WorkRole.courier) MetricTile(label: 'Kiện đã lấy', value: '${summary['pickedUp']}', icon: Icons.inventory_2_outlined),
      if (role.worksAtHub) MetricTile(label: 'Kiện nhập kho', value: '${summary['received']}', icon: Icons.warehouse_outlined),
      if (role == WorkRole.driver) MetricTile(label: 'Kiện lên xe', value: '${summary['dispatched']}', icon: Icons.local_shipping_outlined),
      MetricTile(label: 'Giao thành công', value: '${summary['delivered']}', icon: Icons.check_circle_outline, color: successGreen),
      MetricTile(label: 'Giao thất bại', value: '${summary['deliveryFailed']}', icon: Icons.error_outline, color: Theme.of(context).colorScheme.error),
      if (role != WorkRole.driver) MetricTile(label: 'Tiền đã thu', value: money(summary['collectedAmount']), icon: Icons.payments_outlined),
    ];
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      childAspectRatio: 1.6,
      children: tiles,
    );
  }
}
