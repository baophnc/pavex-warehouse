import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/api.dart';
import '../core/format.dart';
import 'theme.dart';

/// Colour for a parcel/shipment status: green when done, red when something went wrong.
Color statusColor(BuildContext context, String status) {
  switch (status) {
    case 'DELIVERED':
    case 'RETURNED':
    case 'APPROVED':
    case 'COMPLETED':
      return successGreen;
    case 'DELIVERY_FAILED':
    case 'CANCELLED':
    case 'REJECTED':
      return Theme.of(context).colorScheme.error;
    case 'RETURNING':
    case 'SUBMITTED':
    case 'ASSIGNED':
      return warningAmber;
    default:
      return Theme.of(context).colorScheme.primary;
  }
}

class StatusChip extends StatelessWidget {
  const StatusChip(this.label, {super.key, required this.color});

  factory StatusChip.status(BuildContext context, String status) =>
      StatusChip(statusLabel(status), color: statusColor(context, status));

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(99)),
        child: Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 12)),
      );
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key, this.trailing});

  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 20, 4, 8),
        child: Row(
          children: [
            Expanded(child: Text(text, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800))),
            ?trailing,
          ],
        ),
      );
}

class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.title, this.message});

  final IconData icon;
  final String title;
  final String? message;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
        child: Column(
          children: [
            Icon(icon, size: 44, color: Theme.of(context).colorScheme.outline),
            const SizedBox(height: 12),
            Text(title, textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleMedium),
            if (message != null) ...[
              const SizedBox(height: 6),
              Text(message!, textAlign: TextAlign.center, style: TextStyle(color: Theme.of(context).colorScheme.outline)),
            ],
          ],
        ),
      );
}

class ErrorPanel extends StatelessWidget {
  const ErrorPanel({super.key, required this.error, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Icon(Icons.cloud_off_rounded, size: 44, color: Theme.of(context).colorScheme.error),
            const SizedBox(height: 12),
            Text(errorText(error), textAlign: TextAlign.center),
            const SizedBox(height: 12),
            OutlinedButton.icon(onPressed: onRetry, icon: const Icon(Icons.refresh), label: const Text('Thử lại')),
          ],
        ),
      );
}

class MetricTile extends StatelessWidget {
  const MetricTile({super.key, required this.label, required this.value, required this.icon, this.color, this.onTap});

  final String label;
  final String value;
  final IconData icon;
  final Color? color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final tint = color ?? Theme.of(context).colorScheme.primary;
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, size: 20, color: tint),
                  const Spacer(),
                  if (onTap != null) Icon(Icons.chevron_right, size: 18, color: Theme.of(context).colorScheme.outline),
                ],
              ),
              const SizedBox(height: 10),
              Text(value, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 2),
              Text(label, style: TextStyle(color: Theme.of(context).colorScheme.outline, fontSize: 13)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Call and map buttons for the person at the other end of a job.
class ContactActions extends StatelessWidget {
  const ContactActions({super.key, required this.phone, required this.address});

  final String phone;
  final String address;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: phone.isEmpty ? null : () => launchUrl(Uri(scheme: 'tel', path: phone)),
              icon: const Icon(Icons.call),
              label: const Text('Gọi'),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: OutlinedButton.icon(
              onPressed: address.isEmpty
                  ? null
                  : () => launchUrl(
                        Uri.https('www.google.com', '/maps/search/', {'api': '1', 'query': address}),
                        mode: LaunchMode.externalApplication,
                      ),
              icon: const Icon(Icons.map_outlined),
              label: const Text('Chỉ đường'),
            ),
          ),
        ],
      );
}

String errorText(Object error) => error is ApiException ? error.message : 'Đã có lỗi xảy ra. Vui lòng thử lại.';

void showMessage(BuildContext context, String message, {bool error = false}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text(message),
      behavior: SnackBarBehavior.floating,
      backgroundColor: error ? Theme.of(context).colorScheme.error : null,
    ));
}

Future<bool> confirm(BuildContext context, {required String title, required String message, String action = 'Xác nhận'}) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Hủy')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(action)),
        ],
      ),
    ) ??
    false;
