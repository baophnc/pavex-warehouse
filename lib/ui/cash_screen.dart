import 'package:flutter/material.dart';

import '../app.dart';
import '../core/format.dart';
import '../core/session.dart';
import '../data/models.dart';
import 'theme.dart';
import 'widgets.dart';

/// Couriers hand in the cash they collected; hubs follow it until finance approves it.
class CashScreen extends StatelessWidget {
  const CashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final session = AppScope.session(context);
    return session.user!.role == WorkRole.courier ? const _CourierCash() : _HubCash(hub: session.currentHub);
  }
}

class _CourierCash extends StatefulWidget {
  const _CourierCash();

  @override
  State<_CourierCash> createState() => _CourierCashState();
}

class _CourierCashState extends State<_CourierCash> {
  late Future<(List<CashCollection>, List<CashRemittance>)> _data;
  final _selected = <String>{};
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _data = _load();
  }

  Future<(List<CashCollection>, List<CashRemittance>)> _load() async {
    final repository = AppScope.repository(context);
    final collections = repository.myCollections();
    final remittances = repository.myRemittances();
    final result = (await collections, await remittances);
    _selected
      ..clear()
      ..addAll(_inHand(result.$1).map((item) => item.id));
    return result;
  }

  /// Only cash still in the courier's pocket can go into a new hand-over.
  static List<CashCollection> _inHand(List<CashCollection> items) =>
      items.where((item) => item.status == 'HELD' && item.currentHubId == null).toList();

  Future<void> _refresh() async {
    final next = _load();
    setState(() => _data = next);
    await next;
  }

  Future<void> _remit(List<CashCollection> inHand) async {
    final session = AppScope.read(context);
    final hubs = session.hubScope?.hubs ?? const <MyHub>[];
    final chosen = inHand.where((item) => _selected.contains(item.id)).toList();
    final total = chosen.fold<int>(0, (sum, item) => sum + item.amount);
    if (chosen.isEmpty) return;
    if (hubs.isEmpty) {
      showMessage(context, 'Bạn chưa được phân bưu cục để nộp tiền.', error: true);
      return;
    }
    final hub = hubs.length == 1
        ? hubs.first
        : await showModalBottomSheet<MyHub>(
            context: context,
            builder: (context) => SafeArea(
              child: ListView(
                shrinkWrap: true,
                children: [
                  const ListTile(title: Text('Nộp tiền tại bưu cục', style: TextStyle(fontWeight: FontWeight.w800))),
                  for (final hub in hubs) ListTile(title: Text(hub.name), subtitle: Text(hub.code), onTap: () => Navigator.pop(context, hub)),
                ],
              ),
            ),
          );
    if (hub == null || !mounted) return;
    final ok = await confirm(
      context,
      title: 'Nộp ${money(total)}?',
      message: 'Bàn giao ${chosen.length} khoản cho ${hub.name}. Số tiền đưa cho bưu cục phải đúng ${money(total)}.',
      action: 'Nộp tiền',
    );
    if (!ok || !mounted) return;

    setState(() => _busy = true);
    try {
      final remittance = await session.repository.submitRemittance(hub.id, chosen);
      if (mounted) showMessage(context, 'Đã tạo lô nộp tiền ${remittance.remittanceNumber}.');
      await _refresh();
    } catch (error) {
      if (mounted) showMessage(context, errorText(error), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Tiền thu hộ')),
        body: RefreshIndicator(
          onRefresh: _refresh,
          child: FutureBuilder(
            future: _data,
            builder: (context, snapshot) {
              if (snapshot.hasError) return ListView(children: [ErrorPanel(error: snapshot.error!, onRetry: _refresh)]);
              if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
              final (collections, remittances) = snapshot.data!;
              final inHand = _inHand(collections);
              final waiting = collections.where((item) => item.status == 'SUBMITTED').toList();
              final chosenTotal = inHand.where((item) => _selected.contains(item.id)).fold<int>(0, (sum, item) => sum + item.amount);
              int sum(List<CashCollection> items) => items.fold<int>(0, (total, item) => total + item.amount);

              return ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                children: [
                  Row(
                    children: [
                      Expanded(child: MetricTile(label: 'Đang giữ', value: money(sum(inHand)), icon: Icons.account_balance_wallet_outlined, color: warningAmber)),
                      const SizedBox(width: 10),
                      Expanded(child: MetricTile(label: 'Đã nộp, chờ duyệt', value: money(sum(waiting)), icon: Icons.hourglass_top)),
                    ],
                  ),
                  SectionTitle('Tiền đang giữ (${inHand.length})'),
                  if (inHand.isEmpty)
                    const EmptyState(icon: Icons.savings_outlined, title: 'Bạn không giữ khoản tiền nào')
                  else ...[
                    Card(
                      child: Column(
                        children: [
                          for (final item in inHand)
                            CheckboxListTile(
                              value: _selected.contains(item.id),
                              onChanged: (value) => setState(() => value == true ? _selected.add(item.id) : _selected.remove(item.id)),
                              title: Text(money(item.amount), style: const TextStyle(fontWeight: FontWeight.w800)),
                              subtitle: Text(
                                '${item.trackingCode} · thu lúc ${dayTime(item.collectedAt)}'
                                '${item.feeAmount > 0 ? '\nGồm thu hộ ${money(item.codAmount)} + cước ${money(item.feeAmount)}' : ''}',
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      onPressed: _busy || chosenTotal == 0 ? null : () => _remit(inHand),
                      icon: const Icon(Icons.outbox_outlined),
                      label: Text('Nộp ${money(chosenTotal)} về bưu cục'),
                    ),
                  ],
                  SectionTitle('Lịch sử nộp tiền (${remittances.length})'),
                  if (remittances.isEmpty) const EmptyState(icon: Icons.receipt_long_outlined, title: 'Chưa có lần nộp tiền nào'),
                  for (final remittance in remittances)
                    Card(
                      child: ListTile(
                        title: Text('${remittance.remittanceNumber} · ${money(remittance.expectedAmount)}'),
                        subtitle: Text(
                          '${remittance.itemCount} đơn · nộp ${dayTime(remittance.submittedAt)}'
                          '${remittance.rejectionReason != null ? '\nBị trả lại: ${remittance.rejectionReason}' : ''}',
                        ),
                        trailing: StatusChip(cashStatusLabel(remittance.status), color: statusColor(context, remittance.status)),
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      );
}

class _HubCash extends StatefulWidget {
  const _HubCash({required this.hub});

  final MyHub? hub;

  @override
  State<_HubCash> createState() => _HubCashState();
}

class _HubCashState extends State<_HubCash> {
  Future<List<CashCollection>>? _data;
  String? _busyId;

  @override
  void didUpdateWidget(covariant _HubCash oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.hub?.id != widget.hub?.id) _data = _load();
  }

  @override
  void initState() {
    super.initState();
    _data = _load();
  }

  Future<List<CashCollection>>? _load() {
    final hub = widget.hub;
    return hub == null ? null : AppScope.repository(context).hubCollections(hub.id);
  }

  Future<void> _refresh() async {
    final next = _load();
    setState(() => _data = next);
    await next;
  }

  Future<void> _resubmit(CashCollection item) async {
    setState(() => _busyId = item.id);
    try {
      await AppScope.repository(context).resubmitCollection(item.id);
      if (mounted) showMessage(context, 'Đã gửi duyệt lại ${money(item.amount)}.');
      await _refresh();
    } catch (error) {
      if (mounted) showMessage(context, errorText(error), error: true);
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Tiền tại bưu cục')),
        body: _data == null
            ? const EmptyState(icon: Icons.store_mall_directory_outlined, title: 'Bạn chưa được phân bưu cục')
            : RefreshIndicator(
                onRefresh: _refresh,
                child: FutureBuilder<List<CashCollection>>(
                  future: _data,
                  builder: (context, snapshot) {
                    if (snapshot.hasError) return ListView(children: [ErrorPanel(error: snapshot.error!, onRetry: _refresh)]);
                    if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
                    final items = snapshot.data!;
                    final returned = items.where((item) => item.status == 'HELD').toList();
                    final waiting = items.where((item) => item.status == 'SUBMITTED').toList();
                    final approved = items.where((item) => item.status == 'APPROVED').toList();
                    int sum(List<CashCollection> list) => list.fold<int>(0, (total, item) => total + item.amount);

                    Widget section(String title, List<CashCollection> list, {bool resubmittable = false}) => Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            SectionTitle('$title (${list.length}) · ${money(sum(list))}'),
                            if (list.isEmpty)
                              Text('Không có khoản nào.', style: TextStyle(color: Theme.of(context).colorScheme.outline))
                            else
                              Card(
                                child: Column(
                                  children: [
                                    for (final item in list)
                                      ListTile(
                                        title: Text('${item.trackingCode} · ${money(item.amount)}'),
                                        subtitle: Text(
                                          'Thu ${dayTime(item.collectedAt)}'
                                          '${item.lastRejectionReason != null ? '\nLý do trả lại: ${item.lastRejectionReason}' : ''}',
                                        ),
                                        trailing: resubmittable
                                            ? (_busyId == item.id
                                                ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
                                                : TextButton(onPressed: () => _resubmit(item), child: const Text('Gửi lại')))
                                            : null,
                                      ),
                                  ],
                                ),
                              ),
                          ],
                        );

                    return ListView(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                      children: [
                        Card(child: ListTile(leading: const Icon(Icons.store_mall_directory_outlined), title: Text(widget.hub!.name))),
                        section('Bị trả lại, cần kiểm đếm', returned, resubmittable: true),
                        section('Đã nhận, chờ kế toán duyệt', waiting),
                        section('Kế toán đã duyệt', approved),
                      ],
                    );
                  },
                ),
              ),
      );
}
