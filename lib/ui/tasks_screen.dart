import 'package:flutter/material.dart';

import '../app.dart';
import '../core/format.dart';
import '../core/session.dart';
import '../data/models.dart';
import 'delivery_screen.dart';
import 'lookup_screen.dart';
import 'scan_screen.dart';
import 'theme.dart';
import 'widgets.dart';

enum _Filter {
  all('Tất cả'),
  pickup('Lấy hàng'),
  delivery('Giao hàng'),
  hub('Tại kho'),
  lineHaul('Chuyến xe');

  const _Filter(this.label);

  final String label;

  bool matches(WorkTask task) => switch (this) {
        _Filter.all => true,
        _Filter.pickup => task.isPickup,
        _Filter.delivery => task.isDelivery,
        _Filter.hub => task.isHubHandling,
        _Filter.lineHaul => task.isLineHaul,
      };
}

/// The worker's open jobs, and for couriers the parcels they are carrying.
class TasksScreen extends StatefulWidget {
  const TasksScreen({super.key});

  @override
  State<TasksScreen> createState() => _TasksScreenState();
}

class _TasksScreenState extends State<TasksScreen> {
  late Future<(List<WorkTask>, List<HeldDelivery>)> _data;
  _Filter _filter = _Filter.all;
  String? _busyId;

  @override
  void initState() {
    super.initState();
    _data = _load();
  }

  Future<(List<WorkTask>, List<HeldDelivery>)> _load() async {
    final session = AppScope.read(context);
    final tasks = session.repository.tasks();
    final held = session.user!.role == WorkRole.courier
        ? session.repository.heldDeliveries()
        : Future.value(const <HeldDelivery>[]);
    return (await tasks, await held);
  }

  Future<void> _refresh() async {
    final next = _load();
    setState(() => _data = next);
    await next;
  }

  Future<void> _act(WorkTask task, Future<void> Function() action, String done) async {
    setState(() => _busyId = task.assignmentId);
    try {
      await action();
      if (mounted) showMessage(context, done);
      await _refresh();
    } catch (error) {
      if (mounted) showMessage(context, errorText(error), error: true);
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  Future<void> _reject(WorkTask task) async {
    final controller = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Từ chối việc này?'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 500,
          decoration: const InputDecoration(labelText: 'Lý do', hintText: 'Ví dụ: xe hỏng, quá tải'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Hủy')),
          FilledButton(onPressed: () => Navigator.pop(context, controller.text.trim()), child: const Text('Từ chối')),
        ],
      ),
    );
    controller.dispose();
    if (reason == null || reason.isEmpty || !mounted) return;
    await _act(task, () => AppScope.repository(context).rejectTask(task.assignmentId, reason), 'Đã từ chối việc.');
  }

  Future<void> _open(Widget screen) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
    if (mounted) await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final repository = AppScope.repository(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Việc của tôi')),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: FutureBuilder(
          future: _data,
          builder: (context, snapshot) {
            if (snapshot.hasError) return ListView(children: [ErrorPanel(error: snapshot.error!, onRetry: _refresh)]);
            if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
            final (tasks, held) = snapshot.data!;
            final visible = tasks.where(_filter.matches).toList();
            final filters = _Filter.values.where((filter) => filter == _Filter.all || tasks.any(filter.matches)).toList();

            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              children: [
                if (filters.length > 2)
                  Wrap(
                    spacing: 8,
                    children: [
                      for (final filter in filters)
                        ChoiceChip(
                          label: Text(filter.label),
                          selected: _filter == filter,
                          onSelected: (_) => setState(() => _filter = filter),
                        ),
                    ],
                  ),
                if (held.isNotEmpty) ...[
                  const SectionTitle('Hàng đang mang đi giao'),
                  for (final delivery in held)
                    _HeldCard(delivery: delivery, onDeliver: () => _open(DeliveryScreen(target: DeliveryTarget.fromHeld(delivery)))),
                ],
                SectionTitle('Việc được giao (${visible.length})'),
                if (visible.isEmpty)
                  const EmptyState(
                    icon: Icons.task_alt,
                    title: 'Chưa có việc nào',
                    message: 'Vào ca và bật “Sẵn sàng nhận việc” ở tab Hôm nay để được giao việc.',
                  ),
                for (final task in visible)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _TaskCard(
                      task: task,
                      busy: _busyId == task.assignmentId,
                      onAccept: () => _act(task, () => repository.acceptTask(task.assignmentId), 'Đã nhận việc.'),
                      onStart: () => _act(task, () => repository.startTask(task.assignmentId), 'Đã bắt đầu.'),
                      onReject: () => _reject(task),
                      onScan: (action) => _open(ScannerScreen(action: action, hubId: task.isHubHandling ? task.hubId : null)),
                      onDeliver: () => _open(DeliveryScreen(target: DeliveryTarget.fromTask(task))),
                      onDetails: () => _open(LookupScreen(code: task.shipment.trackingCode)),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _TaskCard extends StatelessWidget {
  const _TaskCard({
    required this.task,
    required this.busy,
    required this.onAccept,
    required this.onStart,
    required this.onReject,
    required this.onScan,
    required this.onDeliver,
    required this.onDetails,
  });

  final WorkTask task;
  final bool busy;
  final VoidCallback onAccept;
  final VoidCallback onStart;
  final VoidCallback onReject;
  final void Function(String action) onScan;
  final VoidCallback onDeliver;
  final VoidCallback onDetails;

  @override
  Widget build(BuildContext context) {
    final shipment = task.shipment;
    final contact = task.contact;
    final parcels = shipment.parcels;
    final outForDelivery = parcels.any((parcel) => parcel.status == 'OUT_FOR_DELIVERY');
    final readyForDelivery = parcels.any((parcel) => parcel.status == 'AT_DESTINATION_HUB' || parcel.status == 'DELIVERY_FAILED');

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onDetails,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(_icon, color: Theme.of(context).colorScheme.primary, size: 20),
                  const SizedBox(width: 6),
                  Expanded(child: Text(taskTypeLabel(task.type), style: const TextStyle(fontWeight: FontWeight.w800))),
                  StatusChip(taskStatusLabel(task.status), color: statusColor(context, task.status)),
                ],
              ),
              const SizedBox(height: 8),
              Text(shipment.trackingCode, style: const TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.w700)),
              if (task.isHubHandling || task.isLineHaul)
                Text('Tại: ${task.hubName ?? 'kho trung chuyển'}', style: TextStyle(color: Theme.of(context).colorScheme.outline)),
              const Divider(height: 20),
              Text(contact.contactName, style: const TextStyle(fontWeight: FontWeight.w700)),
              Text(contact.contactPhone),
              Text(contact.full, style: TextStyle(color: Theme.of(context).colorScheme.outline)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 12,
                runSpacing: 4,
                children: [
                  Text('${parcels.length} kiện'),
                  if (task.isDelivery && shipment.amountToCollect > 0)
                    Text('Thu: ${money(shipment.amountToCollect)}', style: const TextStyle(fontWeight: FontWeight.w800, color: warningAmber)),
                  if (parcels.any((parcel) => parcel.isFragile))
                    Text('Hàng dễ vỡ', style: TextStyle(color: Theme.of(context).colorScheme.error, fontWeight: FontWeight.w700)),
                ],
              ),
              if (shipment.note != null) ...[
                const SizedBox(height: 6),
                Text('Ghi chú: ${shipment.note}', style: const TextStyle(fontStyle: FontStyle.italic)),
              ],
              if (task.isPickup || task.isDelivery) ...[
                const SizedBox(height: 12),
                ContactActions(phone: contact.contactPhone, address: contact.full),
              ],
              const SizedBox(height: 12),
              if (busy)
                const Center(child: CircularProgressIndicator())
              else if (task.awaitingAcceptance)
                Row(
                  children: [
                    Expanded(child: OutlinedButton(onPressed: onReject, child: const Text('Từ chối'))),
                    const SizedBox(width: 10),
                    Expanded(child: FilledButton(onPressed: onAccept, child: const Text('Nhận việc'))),
                  ],
                )
              else if (task.awaitingStart)
                SizedBox(width: double.infinity, child: FilledButton(onPressed: onStart, child: const Text('Bắt đầu')))
              else if (task.inProgress)
                ..._progressActions(outForDelivery, readyForDelivery),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _progressActions(bool outForDelivery, bool readyForDelivery) {
    Widget full(Widget button) => SizedBox(width: double.infinity, child: button);
    if (task.isPickup) {
      return [full(FilledButton.icon(onPressed: () => onScan('PICK_UP'), icon: const Icon(Icons.qr_code_scanner), label: const Text('Quét lấy hàng')))];
    }
    if (task.isLineHaul) {
      return [full(FilledButton.icon(onPressed: () => onScan('DEPART'), icon: const Icon(Icons.qr_code_scanner), label: const Text('Quét lên xe')))];
    }
    if (task.isHubHandling) {
      return [full(FilledButton.icon(onPressed: () => onScan('RECEIVE'), icon: const Icon(Icons.qr_code_scanner), label: const Text('Quét nhập kho')))];
    }
    return [
      if (readyForDelivery)
        full(OutlinedButton.icon(onPressed: () => onScan('OUT_FOR_DELIVERY'), icon: const Icon(Icons.qr_code_scanner), label: const Text('Quét xuất giao'))),
      if (readyForDelivery && outForDelivery) const SizedBox(height: 8),
      if (outForDelivery) full(FilledButton.icon(onPressed: onDeliver, icon: const Icon(Icons.done_all), label: const Text('Giao hàng'))),
    ];
  }

  IconData get _icon => switch (task.type) {
        'PICKUP' => Icons.move_to_inbox_outlined,
        'LAST_MILE_DELIVERY' => Icons.local_shipping_outlined,
        'LINE_HAUL' => Icons.fire_truck_outlined,
        _ => Icons.warehouse_outlined,
      };
}

class _HeldCard extends StatelessWidget {
  const _HeldCard({required this.delivery, required this.onDeliver});

  final HeldDelivery delivery;
  final VoidCallback onDeliver;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(child: Text(delivery.trackingCode, style: const TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.w800))),
                    StatusChip.status(context, delivery.status),
                  ],
                ),
                const SizedBox(height: 6),
                Text(delivery.recipient.contactName, style: const TextStyle(fontWeight: FontWeight.w700)),
                Text(delivery.recipient.full, style: TextStyle(color: Theme.of(context).colorScheme.outline)),
                if (delivery.needsCollection)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text('Thu: ${money(delivery.amountToCollect)}', style: const TextStyle(fontWeight: FontWeight.w800, color: warningAmber)),
                  ),
                const SizedBox(height: 12),
                ContactActions(phone: delivery.recipient.contactPhone, address: delivery.recipient.full),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(onPressed: onDeliver, icon: const Icon(Icons.done_all), label: const Text('Giao hàng')),
                ),
              ],
            ),
          ),
        ),
      );
}
