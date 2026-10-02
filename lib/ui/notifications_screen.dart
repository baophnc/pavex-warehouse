import 'dart:async';

import 'package:flutter/material.dart';

import '../app.dart';
import '../data/models.dart';
import 'theme.dart';
import 'widgets.dart';

/// The bell in the app bar: the unread count, refreshed every minute and when the inbox closes.
class NotificationBell extends StatefulWidget {
  const NotificationBell({super.key});

  @override
  State<NotificationBell> createState() => _NotificationBellState();
}

class _NotificationBellState extends State<NotificationBell> {
  int _count = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
    _timer = Timer.periodic(const Duration(minutes: 1), (_) => _refresh());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    try {
      final count = await AppScope.repository(context).unreadNotifications();
      if (mounted) setState(() => _count = count);
    } catch (_) {
      // The bell is a hint; it retries on the next tick.
    }
  }

  @override
  Widget build(BuildContext context) => IconButton(
        tooltip: 'Thông báo',
        onPressed: () async {
          await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const NotificationsScreen()));
          await _refresh();
        },
        icon: Badge(
          isLabelVisible: _count > 0,
          label: Text(_count > 99 ? '99+' : '$_count'),
          child: const Icon(Icons.notifications_outlined),
        ),
      );
}

/// The worker's inbox, and for hub managers and staff a way to write to their hub.
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  List<AppNotification>? _items;
  String? _cursor;
  Object? _error;
  MessageOptions? _options;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _load();
      AppScope.repository(context).messageOptions().then((value) {
        if (mounted) setState(() => _options = value);
      }).catchError((_) {});
    });
  }

  Future<void> _load({bool more = false}) async {
    try {
      final page = await AppScope.repository(context).notifications(cursor: more ? _cursor : null);
      if (!mounted) return;
      setState(() {
        _items = more ? [...?_items, ...page.items] : page.items;
        _cursor = page.nextCursor;
        _error = null;
      });
    } catch (error) {
      if (mounted) setState(() => _error = error);
    }
  }

  Future<void> _open(AppNotification item) async {
    if (!item.isRead) {
      await AppScope.repository(context).markNotificationRead(item.id).catchError((_) {});
      if (mounted) setState(() => _items = _items?.map((value) => value.id == item.id ? value.read() : value).toList());
    }
  }

  Future<void> _readAll() async {
    await AppScope.repository(context).markAllNotificationsRead().catchError((_) {});
    if (mounted) setState(() => _items = _items?.map((value) => value.read()).toList());
  }

  @override
  Widget build(BuildContext context) {
    final canCompose = (_options?.audiences.isNotEmpty ?? false);
    final items = _items;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Thông báo'),
        actions: [
          if (items?.any((item) => !item.isRead) ?? false)
            TextButton(onPressed: _readAll, child: const Text('Đọc hết')),
        ],
      ),
      floatingActionButton: canCompose
          ? FloatingActionButton.extended(
              onPressed: () async {
                final sent = await Navigator.of(context).push<bool>(
                  MaterialPageRoute(builder: (_) => HubMessageScreen(options: _options!)),
                );
                if (sent == true && context.mounted) showMessage(context, 'Đã gửi thông báo.');
              },
              icon: const Icon(Icons.campaign_outlined),
              label: const Text('Gửi thông báo'),
            )
          : null,
      body: RefreshIndicator(
        onRefresh: _load,
        child: _error != null
            ? ListView(children: [ErrorPanel(error: _error!, onRetry: _load)])
            : items == null
                ? const Center(child: CircularProgressIndicator())
                : items.isEmpty
                    ? ListView(children: const [
                        EmptyState(icon: Icons.notifications_none, title: 'Chưa có thông báo', message: 'Khi có việc mới hay tin nhắn từ bưu cục, bạn sẽ thấy ở đây.'),
                      ])
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(0, 8, 0, 96),
                        itemCount: items.length + (_cursor != null ? 1 : 0),
                        separatorBuilder: (_, _) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          if (index == items.length) {
                            return Center(child: TextButton(onPressed: () => _load(more: true), child: const Text('Xem thêm')));
                          }
                          final item = items[index];
                          return ListTile(
                            onTap: () => _open(item),
                            tileColor: item.isRead ? null : Theme.of(context).colorScheme.primaryContainer,
                            leading: Icon(
                              item.isMessage ? Icons.campaign_outlined : _icon(item.code),
                              color: _tone(item.severity),
                            ),
                            title: Text(item.title, style: TextStyle(fontWeight: item.isRead ? FontWeight.w600 : FontWeight.w800)),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const SizedBox(height: 2),
                                Text(item.body),
                                const SizedBox(height: 4),
                                Text(_ago(item.createdAt), style: Theme.of(context).textTheme.bodySmall),
                              ],
                            ),
                            isThreeLine: true,
                          );
                        },
                      ),
      ),
    );
  }

  static IconData _icon(String code) {
    if (code.startsWith('operations.assignment')) return Icons.assignment_outlined;
    if (code.startsWith('shipment.case')) return Icons.report_problem_outlined;
    if (code.startsWith('billing')) return Icons.payments_outlined;
    return Icons.notifications_outlined;
  }

  static Color? _tone(String severity) => switch (severity) {
        'Critical' => pavexRed,
        'Warning' => warningAmber,
        'Success' => successGreen,
        _ => null,
      };

  static String _ago(DateTime at) {
    final minutes = DateTime.now().difference(at).inMinutes;
    if (minutes < 1) return 'Vừa xong';
    if (minutes < 60) return '$minutes phút trước';
    if (minutes < 24 * 60) return '${minutes ~/ 60} giờ trước';
    return '${at.day}/${at.month} ${at.hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')}';
  }
}

/// A hub manager or hub staff writes to the people of their hub.
class HubMessageScreen extends StatefulWidget {
  const HubMessageScreen({super.key, required this.options});

  final MessageOptions options;

  @override
  State<HubMessageScreen> createState() => _HubMessageScreenState();
}

class _HubMessageScreenState extends State<HubMessageScreen> {
  final _title = TextEditingController();
  final _body = TextEditingController();
  late String _audience = widget.options.audiences.first;
  String? _hubId;
  bool _sending = false;

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  Future<void> _send(String hubId) async {
    if (_title.text.trim().isEmpty || _body.text.trim().isEmpty) {
      showMessage(context, 'Nhập tiêu đề và nội dung.', error: true);
      return;
    }
    setState(() => _sending = true);
    try {
      final count = await AppScope.repository(context)
          .sendHubMessage(audience: _audience, hubId: hubId, title: _title.text.trim(), body: _body.text.trim());
      if (!mounted) return;
      showMessage(context, 'Đã gửi tới $count người.');
      Navigator.of(context).pop(true);
    } catch (error) {
      if (mounted) showMessage(context, errorText(error), error: true);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final hubs = (AppScope.session(context).hubScope?.hubs ?? const <MyHub>[])
        .where((hub) => widget.options.hubIds.contains(hub.id))
        .toList();
    final hubId = _hubId ?? (hubs.isEmpty ? null : hubs.first.id);
    return Scaffold(
      appBar: AppBar(title: const Text('Gửi thông báo')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (hubs.length > 1) ...[
            DropdownButtonFormField<String>(
              initialValue: hubId,
              decoration: const InputDecoration(labelText: 'Bưu cục'),
              items: [for (final hub in hubs) DropdownMenuItem(value: hub.id, child: Text('${hub.code} · ${hub.name}'))],
              onChanged: (value) => setState(() => _hubId = value),
            ),
            const SizedBox(height: 12),
          ],
          DropdownButtonFormField<String>(
            initialValue: _audience,
            decoration: const InputDecoration(labelText: 'Gửi cho'),
            items: [
              for (final audience in widget.options.audiences)
                DropdownMenuItem(value: audience, child: Text(MessageOptions.audienceLabels[audience] ?? audience)),
            ],
            onChanged: (value) => setState(() => _audience = value ?? _audience),
          ),
          const SizedBox(height: 12),
          TextField(controller: _title, maxLength: 160, decoration: const InputDecoration(labelText: 'Tiêu đề')),
          TextField(controller: _body, maxLength: 1000, minLines: 3, maxLines: 6, decoration: const InputDecoration(labelText: 'Nội dung')),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _sending || hubId == null ? null : () => _send(hubId),
            icon: const Icon(Icons.send),
            label: const Text('Gửi'),
          ),
        ],
      ),
    );
  }
}

/// Ask for a short message to the shop that sent this shipment, and send it.
Future<void> messageShop(BuildContext context, String trackingCode) async {
  final controller = TextEditingController();
  final body = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Nhắn shop'),
      content: TextField(
        controller: controller,
        autofocus: true,
        maxLength: 1000,
        minLines: 2,
        maxLines: 5,
        decoration: InputDecoration(hintText: 'Ví dụ: Em tới lấy hàng lúc 15h, shop chuẩn bị giúp em nhé.', helperText: 'Vận đơn $trackingCode'),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Huỷ')),
        FilledButton(onPressed: () => Navigator.of(context).pop(controller.text.trim()), child: const Text('Gửi')),
      ],
    ),
  );
  controller.dispose();
  if (body == null || body.isEmpty || !context.mounted) return;
  try {
    await AppScope.repository(context).messageShop(trackingCode, body);
    if (context.mounted) showMessage(context, 'Đã nhắn shop.');
  } catch (error) {
    if (context.mounted) showMessage(context, errorText(error), error: true);
  }
}
