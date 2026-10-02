import 'package:flutter/material.dart';

import '../app.dart';
import '../core/format.dart';
import '../data/models.dart';
import 'notifications_screen.dart';
import 'theme.dart';
import 'widgets.dart';

/// A scanned or typed shipment: who, what, where it has been, and what you can do now.
class LookupScreen extends StatefulWidget {
  const LookupScreen({super.key, required this.code});

  final String code;

  @override
  State<LookupScreen> createState() => _LookupScreenState();
}

class _LookupScreenState extends State<LookupScreen> {
  late Future<LookupResult> _data;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _data = AppScope.repository(context).lookup(widget.code);
  }

  Future<void> _refresh() async {
    final next = AppScope.repository(context).lookup(widget.code);
    setState(() => _data = next);
    await next;
  }

  Future<void> _perform(String action) async {
    final session = AppScope.read(context);
    final repository = session.repository;
    setState(() => _busy = true);
    try {
      var response = await repository.scan(widget.code, action, hubId: session.currentHub?.id);
      // The job is the worker's but not started yet: start it, as the continuous scanner does.
      final startable = response.results
          .where((result) => result.code == 'assignment_not_started' && result.assignmentId != null)
          .firstOrNull;
      if (startable != null) {
        try {
          await repository.acceptTask(startable.assignmentId!);
        } catch (_) {
          // Already accepted: starting is what matters.
        }
        await repository.startTask(startable.assignmentId!);
        response = await repository.scan(widget.code, action, hubId: session.currentHub?.id);
      }
      final failed = response.results.where((result) => !result.ok).toList();
      if (mounted) {
        showMessage(
          context,
          failed.isEmpty ? response.results.map((result) => result.message).toSet().join(' ') : failed.first.message,
          error: failed.isNotEmpty,
        );
      }
    } catch (error) {
      if (mounted) showMessage(context, errorText(error), error: true);
    }
    if (!mounted) return;
    setState(() => _busy = false);
    await _refresh().catchError((_) {});
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: Text(widget.code, style: const TextStyle(fontFamily: 'monospace')),
          actions: [
            IconButton(
              tooltip: 'Nhắn shop',
              icon: const Icon(Icons.chat_outlined),
              onPressed: () => messageShop(context, widget.code.split('-').take(1).join()),
            ),
          ],
        ),
        body: RefreshIndicator(
          onRefresh: _refresh,
          child: FutureBuilder<LookupResult>(
            future: _data,
            builder: (context, snapshot) {
              if (snapshot.hasError) return ListView(children: [ErrorPanel(error: snapshot.error!, onRetry: _refresh)]);
              if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
              final result = snapshot.data!;
              final shipment = result.shipment;
              return ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                children: [
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(shipment.trackingCode, style: const TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.w800)),
                              ),
                              StatusChip.status(context, shipment.status),
                            ],
                          ),
                          if (shipment.merchantReference != null) Text('Mã đơn shop: ${shipment.merchantReference}'),
                          const SizedBox(height: 8),
                          Text('${shipment.originHubName} → ${shipment.destinationHubName}'),
                          if (shipment.amountToCollect > 0)
                            Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Text(
                                shipment.needsCollection
                                    ? 'Cần thu người nhận: ${money(shipment.amountToCollect)}'
                                    : 'Đã thu ${money(shipment.amountToCollect)}',
                                style: TextStyle(fontWeight: FontWeight.w800, color: shipment.needsCollection ? warningAmber : successGreen),
                              ),
                            ),
                          if (shipment.note != null)
                            Padding(padding: const EdgeInsets.only(top: 8), child: Text('Ghi chú: ${shipment.note}')),
                        ],
                      ),
                    ),
                  ),
                  if (result.suggestedActions.isNotEmpty) ...[
                    const SectionTitle('Thao tác'),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        for (final action in result.suggestedActions)
                          FilledButton.icon(
                            onPressed: _busy ? null : () => _perform(action),
                            icon: const Icon(Icons.bolt),
                            label: Text(scanActionLabel(action)),
                          ),
                      ],
                    ),
                  ],
                  const SectionTitle('Người gửi'),
                  _AddressCard(address: shipment.sender),
                  const SectionTitle('Người nhận'),
                  _AddressCard(address: shipment.recipient),
                  SectionTitle('Kiện hàng (${shipment.parcels.length})'),
                  for (final parcel in shipment.parcels)
                    Card(
                      child: ListTile(
                        title: Text(parcel.parcelCode, style: const TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.w700)),
                        subtitle: Text(
                          '${parcel.description} · ${parcel.weightKg.toStringAsFixed(2)} kg'
                          '${parcel.isFragile ? ' · Dễ vỡ' : ''}'
                          '${parcel.currentHubName != null ? '\nĐang ở: ${parcel.currentHubName}' : ''}',
                        ),
                        trailing: StatusChip.status(context, parcel.status),
                      ),
                    ),
                  const SectionTitle('Hành trình'),
                  for (final event in result.timeline)
                    ListTile(
                      dense: true,
                      leading: Icon(Icons.circle, size: 10, color: statusColor(context, event.status)),
                      title: Text(event.description),
                      subtitle: Text([dayTime(event.occurredAt), event.locationName].whereType<String>().join(' · ')),
                    ),
                ],
              );
            },
          ),
        ),
      );
}

class _AddressCard extends StatelessWidget {
  const _AddressCard({required this.address});

  final Address address;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(address.contactName, style: const TextStyle(fontWeight: FontWeight.w700)),
              Text(address.contactPhone),
              Text(address.full, style: TextStyle(color: Theme.of(context).colorScheme.outline)),
              const SizedBox(height: 10),
              ContactActions(phone: address.contactPhone, address: address.full),
            ],
          ),
        ),
      );
}
