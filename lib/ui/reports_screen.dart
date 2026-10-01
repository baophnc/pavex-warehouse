import 'package:flutter/material.dart';

import '../app.dart';
import '../core/format.dart';
import '../core/session.dart';
import '../data/models.dart';
import 'lookup_screen.dart';
import 'theme.dart';
import 'widgets.dart';

class _ReportData {
  _ReportData(this.summary, this.collections, this.remittances);

  final ReportSummary summary;
  final List<CashCollection> collections;
  final List<CashRemittance> remittances;
}

/// Work done and money handled over a period, for the worker or for their hub.
class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  DateRange _range = DateRange.today();
  bool _hubView = true;
  Future<_ReportData>? _data;
  String? _loadedFor;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final hubId = AppScope.session(context).currentHub?.id;
    if (_loadedFor != hubId || _data == null) {
      _loadedFor = hubId;
      _data = _load();
    }
  }

  String? get _hubId {
    final session = AppScope.read(context);
    return session.user!.role.worksAtHub && _hubView ? session.currentHub?.id : null;
  }

  Future<_ReportData> _load() async {
    final session = AppScope.read(context);
    final repository = session.repository;
    final role = session.user!.role;
    final hubId = _hubId;
    final summary = repository.reportSummary(_range, hubId: hubId);
    final collections = !role.handlesCash
        ? Future.value(const <CashCollection>[])
        : hubId != null
            ? repository.hubCollections(hubId)
            : repository.myCollections();
    final remittances = role == WorkRole.courier && hubId == null ? repository.myRemittances() : Future.value(const <CashRemittance>[]);
    return _ReportData(await summary, await collections, await remittances);
  }

  Future<void> _refresh() async {
    final next = _load();
    setState(() => _data = next);
    await next;
  }

  void _setRange(DateRange range) {
    _range = range;
    _refresh();
  }

  void _open(String kind, String title) => Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => ReportListScreen(kind: kind, title: title, range: _range, hubId: _hubId),
      ));

  @override
  Widget build(BuildContext context) {
    final session = AppScope.session(context);
    final role = session.user!.role;
    return Scaffold(
      appBar: AppBar(title: const Text('Báo cáo')),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            Wrap(
              spacing: 8,
              children: [
                for (final range in [DateRange.today(), DateRange.lastDays(7), DateRange.thisMonth()])
                  ChoiceChip(label: Text(range.label), selected: _range.label == range.label, onSelected: (_) => _setRange(range)),
              ],
            ),
            if (role.worksAtHub) ...[
              const SizedBox(height: 10),
              SegmentedButton<bool>(
                segments: [
                  ButtonSegment(value: true, icon: const Icon(Icons.store_mall_directory_outlined), label: Text(session.currentHub?.name ?? 'Bưu cục')),
                  const ButtonSegment(value: false, icon: Icon(Icons.person_outline), label: Text('Cá nhân')),
                ],
                selected: {_hubView},
                onSelectionChanged: (value) {
                  _hubView = value.first;
                  _refresh();
                },
              ),
            ],
            const SizedBox(height: 4),
            Text('${day(_range.from)} – ${day(_range.to)}', style: TextStyle(color: Theme.of(context).colorScheme.outline)),
            FutureBuilder<_ReportData>(
              future: _data,
              builder: (context, snapshot) {
                if (snapshot.hasError) return ErrorPanel(error: snapshot.error!, onRetry: _refresh);
                if (!snapshot.hasData) {
                  return const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator()));
                }
                final data = snapshot.data!;
                final hubView = _hubId != null;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SectionTitle('Sản lượng'),
                    _grid([
                      if (!hubView && role == WorkRole.courier)
                        MetricTile(label: 'Kiện đã lấy', value: '${data.summary['pickedUp']}', icon: Icons.move_to_inbox_outlined),
                      if (hubView) MetricTile(label: 'Kiện nhập kho', value: '${data.summary['received']}', icon: Icons.warehouse_outlined),
                      if (hubView || role == WorkRole.driver)
                        MetricTile(label: hubView ? 'Kiện xuất kho' : 'Kiện lên xe', value: '${data.summary['dispatched']}', icon: Icons.fire_truck_outlined),
                      if (hubView)
                        MetricTile(
                          label: 'Tồn kho hiện tại',
                          value: '${data.summary['inStock']}',
                          icon: Icons.shelves,
                          onTap: () => _open('IN_STOCK', 'Hàng tồn kho'),
                        ),
                      MetricTile(label: 'Đi giao', value: '${data.summary['outForDelivery']}', icon: Icons.local_shipping_outlined),
                      MetricTile(
                        label: 'Giao thành công',
                        value: '${data.summary['delivered']}',
                        icon: Icons.check_circle_outline,
                        color: successGreen,
                        onTap: () => _open('DELIVERED', 'Giao thành công'),
                      ),
                      MetricTile(
                        label: 'Giao thất bại',
                        value: '${data.summary['deliveryFailed']}',
                        icon: Icons.error_outline,
                        color: Theme.of(context).colorScheme.error,
                        onTap: () => _open('DELIVERY_FAILED', 'Giao thất bại'),
                      ),
                    ]),
                    const SectionTitle('Hàng hủy & hàng hoàn'),
                    _grid([
                      MetricTile(
                        label: 'Hàng hủy',
                        value: '${data.summary['cancelled']}',
                        icon: Icons.block,
                        color: Theme.of(context).colorScheme.error,
                        onTap: () => _open('CANCELLED', 'Hàng hủy'),
                      ),
                      MetricTile(
                        label: 'Đang hoàn',
                        value: '${data.summary['returning']}',
                        icon: Icons.u_turn_left,
                        color: warningAmber,
                        onTap: () => _open('RETURNING', 'Hàng đang hoàn'),
                      ),
                      MetricTile(
                        label: 'Đã hoàn về',
                        value: '${data.summary['returned']}',
                        icon: Icons.assignment_return_outlined,
                        onTap: () => _open('RETURNED', 'Hàng đã hoàn'),
                      ),
                    ]),
                    if (role.handlesCash) ...[
                      const SectionTitle('Thu chi'),
                      _CashSummary(data: data, range: _range, hubView: hubView),
                    ],
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _grid(List<Widget> tiles) => GridView.count(
        crossAxisCount: 2,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: 1.6,
        children: tiles,
      );
}

/// Money in (collected from recipients) against money out (handed to the hub / approved by finance).
class _CashSummary extends StatelessWidget {
  const _CashSummary({required this.data, required this.range, required this.hubView});

  final _ReportData data;
  final DateRange range;
  final bool hubView;

  @override
  Widget build(BuildContext context) {
    int sum(Iterable<CashCollection> items) => items.fold<int>(0, (total, item) => total + item.amount);
    final rows = <(String, int, Color?)>[
      ('Thu từ người nhận trong kỳ (${data.summary['collectedShipments']} đơn)', data.summary['collectedAmount'], successGreen),
      if (!hubView) ...[
        (
          'Đã nộp về bưu cục trong kỳ',
          data.remittances.where((item) => item.status != 'REJECTED' && range.contains(item.submittedAt)).fold<int>(0, (total, item) => total + item.expectedAmount),
          null,
        ),
        ('Kế toán đã duyệt trong kỳ', data.remittances.where((item) => range.contains(item.approvedAt)).fold<int>(0, (total, item) => total + item.expectedAmount), null),
        ('Đang giữ, chưa nộp', sum(data.collections.where((item) => item.status == 'HELD' && item.currentHubId == null)), warningAmber),
      ] else ...[
        ('Đã nhận, chờ kế toán duyệt', sum(data.collections.where((item) => item.status == 'SUBMITTED')), null),
        ('Kế toán đã duyệt', sum(data.collections.where((item) => item.status == 'APPROVED')), successGreen),
        ('Bị trả lại, cần kiểm đếm', sum(data.collections.where((item) => item.status == 'HELD')), Theme.of(context).colorScheme.error),
      ],
    ];
    return Card(
      child: Column(
        children: [
          for (final (label, amount, color) in rows)
            ListTile(
              dense: true,
              title: Text(label),
              trailing: Text(money(amount), style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: color)),
            ),
        ],
      ),
    );
  }
}

class ReportListScreen extends StatelessWidget {
  const ReportListScreen({super.key, required this.kind, required this.title, required this.range, this.hubId});

  final String kind;
  final String title;
  final DateRange range;
  final String? hubId;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(title)),
        body: FutureBuilder<List<ReportItem>>(
          future: AppScope.repository(context).reportItems(kind, range, hubId: hubId),
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return ErrorPanel(error: snapshot.error!, onRetry: () => Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => this)));
            }
            if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
            final items = snapshot.data!;
            if (items.isEmpty) return const EmptyState(icon: Icons.inbox_outlined, title: 'Không có đơn nào trong kỳ này');
            return ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: items.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final item = items[index];
                return Card(
                  child: ListTile(
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => LookupScreen(code: item.trackingCode))),
                    title: Text(item.trackingCode, style: const TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.w700)),
                    subtitle: Text(
                      '${item.recipientName} · ${item.recipientPhone}\n${item.recipientAddress}'
                      '${item.reason != null ? '\n${item.reason}' : ''}'
                      '\n${dayTime(item.occurredAt)}${item.amountToCollect > 0 ? ' · thu ${money(item.amountToCollect)}' : ''}',
                    ),
                    isThreeLine: true,
                    trailing: StatusChip.status(context, item.status),
                  ),
                );
              },
            );
          },
        ),
      );
}
