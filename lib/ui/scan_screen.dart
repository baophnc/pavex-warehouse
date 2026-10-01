import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../app.dart';
import '../core/format.dart';
import '../core/session.dart';
import '../data/models.dart';
import 'lookup_screen.dart';
import 'theme.dart';
import 'trips_screen.dart';
import 'widgets.dart';

/// Pulls a Pavex tracking or parcel code out of whatever the camera read
/// (a bare code, or a tracking link).
String? extractCode(String raw) =>
    RegExp(r'PAVEX[0-9]{6}[0-9A-Z]{10}(?:-[0-9]{2})?').firstMatch(raw.toUpperCase())?.group(0);

class _ScanMode {
  const _ScanMode(this.action, this.title, this.description, this.icon);

  final String action;
  final String title;
  final String description;
  final IconData icon;
}

const _pickUp = _ScanMode('PICK_UP', 'Lấy hàng', 'Quét kiện khi nhận hàng từ người gửi.', Icons.move_to_inbox_outlined);
const _outForDelivery = _ScanMode('OUT_FOR_DELIVERY', 'Xuất giao', 'Quét kiện khi mang ra khỏi bưu cục đi giao.', Icons.local_shipping_outlined);
const _receive = _ScanMode('RECEIVE', 'Nhập kho', 'Quét kiện bưu tá mang về, xe trung chuyển dỡ xuống hoặc hàng hoàn.', Icons.warehouse_outlined);
const _check = _ScanMode('CHECK', 'Kiểm kho', 'Quét để xác nhận kiện đang nằm trên kệ.', Icons.fact_check_outlined);
const _depart = _ScanMode('DEPART', 'Lên xe', 'Quét kiện khi chất lên xe trung chuyển.', Icons.fire_truck_outlined);
const _lookup = _ScanMode('LOOKUP', 'Tra cứu', 'Xem thông tin và hành trình của đơn.', Icons.search);

List<_ScanMode> _modesFor(WorkRole role) => switch (role) {
      WorkRole.courier => const [_pickUp, _outForDelivery, _lookup],
      WorkRole.hubManager || WorkRole.hubStaff => const [_receive, _check, _lookup],
      WorkRole.driver => const [_depart, _lookup],
      WorkRole.unsupported => const [_lookup],
    };

/// Pick what you are doing, then scan.
class ScanHubScreen extends StatefulWidget {
  const ScanHubScreen({super.key});

  @override
  State<ScanHubScreen> createState() => _ScanHubScreenState();
}

class _ScanHubScreenState extends State<ScanHubScreen> {
  final _code = TextEditingController();

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  void _lookupTyped() {
    final code = extractCode(_code.text);
    if (code == null) {
      showMessage(context, 'Mã không đúng định dạng PAVEX…', error: true);
      return;
    }
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => LookupScreen(code: code)));
  }

  @override
  Widget build(BuildContext context) {
    final session = AppScope.session(context);
    final role = session.user!.role;
    return Scaffold(
      appBar: AppBar(title: const Text('Quét mã')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          if (role.worksAtHub)
            Card(
              child: ListTile(
                leading: const Icon(Icons.store_mall_directory_outlined),
                title: Text(session.currentHub?.name ?? 'Chưa được phân bưu cục'),
                subtitle: const Text('Bưu cục đang làm việc (đổi ở tab Hôm nay)'),
              ),
            ),
          const SectionTitle('Bạn đang làm gì?'),
          for (final mode in _modesFor(role))
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Card(
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  leading: CircleAvatar(
                    backgroundColor: pavexRed.withValues(alpha: 0.1),
                    child: Icon(mode.icon, color: pavexRed),
                  ),
                  title: Text(mode.title, style: const TextStyle(fontWeight: FontWeight.w800)),
                  subtitle: Text(mode.description),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ScannerScreen(action: mode.action))),
                ),
              ),
            ),
          const SectionTitle('Hoặc nhập mã'),
          TextField(
            controller: _code,
            textCapitalization: TextCapitalization.characters,
            onSubmitted: (_) => _lookupTyped(),
            decoration: InputDecoration(
              hintText: 'PAVEX2609…',
              prefixIcon: const Icon(Icons.keyboard_outlined),
              suffixIcon: IconButton(icon: const Icon(Icons.search), onPressed: _lookupTyped),
            ),
          ),
        ],
      ),
    );
  }
}

class _ScanEntry {
  _ScanEntry(this.code, {this.response, this.error});

  final String code;
  final ScanResponse? response;
  final String? error;
  final DateTime at = DateTime.now();

  bool get ok => error == null && response != null && response!.results.isNotEmpty && response!.results.every((item) => item.ok);

  ScanResult? get startable =>
      response?.results.where((item) => item.code == 'assignment_not_started' && item.assignmentId != null).firstOrNull;
}

/// Continuous scanning for one kind of work; each code is sent as soon as it is read.
class ScannerScreen extends StatefulWidget {
  const ScannerScreen({super.key, required this.action, this.hubId});

  final String action;

  /// The hub for RECEIVE/CHECK; defaults to the worker's current hub.
  final String? hubId;

  @override
  State<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends State<ScannerScreen> {
  final _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.normal,
    formats: const [BarcodeFormat.qrCode, BarcodeFormat.code128, BarcodeFormat.code39, BarcodeFormat.dataMatrix],
  );
  final _entries = <_ScanEntry>[];
  final _recent = <String, DateTime>{};
  final _pending = <String>{};

  bool get _isLookup => widget.action == 'LOOKUP';

  @override
  void dispose() {
    unawaited(_controller.dispose());
    super.dispose();
  }

  String? get _hubId => widget.hubId ?? AppScope.read(context).currentHub?.id;

  void _onDetect(BarcodeCapture capture) {
    for (final barcode in capture.barcodes) {
      final code = extractCode(barcode.rawValue ?? '');
      if (code != null) _handle(code);
    }
  }

  Future<void> _handle(String code) async {
    final last = _recent[code];
    if (_pending.contains(code) || (last != null && DateTime.now().difference(last) < const Duration(seconds: 3))) return;
    _recent[code] = DateTime.now();

    if (_isLookup) {
      await _controller.stop();
      if (!mounted) return;
      await Navigator.of(context).push(MaterialPageRoute(builder: (_) => LookupScreen(code: code)));
      if (mounted) await _controller.start();
      return;
    }

    final hubId = _hubId;
    if ((widget.action == 'RECEIVE' || widget.action == 'CHECK') && hubId == null) {
      showMessage(context, 'Bạn chưa được phân bưu cục nên chưa nhập kho được.', error: true);
      return;
    }

    _pending.add(code);
    try {
      final response = await AppScope.repository(context).scan(code, widget.action, hubId: hubId);
      final entry = _ScanEntry(code, response: response);
      entry.ok ? HapticFeedback.lightImpact() : HapticFeedback.heavyImpact();
      if (mounted) setState(() => _entries.insert(0, entry));
      if (widget.action == 'DEPART' && entry.ok) unawaited(_startTripFromScan());
    } catch (error) {
      HapticFeedback.heavyImpact();
      if (mounted) setState(() => _entries.insert(0, _ScanEntry(code, error: errorText(error))));
    } finally {
      _pending.remove(code);
    }
  }

  /// Loading the first parcel starts the line-haul trip, so the truck's position is sent from here on.
  Future<void> _startTripFromScan() async {
    final session = AppScope.read(context);
    if (session.trips.active) return;
    try {
      final trip = await session.repository.startTripFromScan();
      final tripId = trip?.tripId;
      if (trip == null || tripId == null) return;
      await session.trips.resume(tripId);
      if (mounted) showMessage(context, 'Đã bắt đầu chuyến ${trip.fromHubCode} → ${trip.toHubCode}. Đang gửi vị trí xe.');
    } catch (error) {
      if (mounted) showMessage(context, tripErrorText(error), error: true);
    }
  }

  /// Accepts and starts the job the server asked for, then scans the code again.
  Future<void> _startAndRetry(_ScanEntry entry) async {
    final startable = entry.startable!;
    final repository = AppScope.repository(context);
    try {
      try {
        await repository.acceptTask(startable.assignmentId!);
      } catch (_) {
        // Already accepted: starting is what matters.
      }
      await repository.startTask(startable.assignmentId!);
      _recent.remove(entry.code);
      await _handle(entry.code);
    } catch (error) {
      if (mounted) showMessage(context, errorText(error), error: true);
    }
  }

  Future<void> _typeCode() async {
    final controller = TextEditingController();
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Nhập mã'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.characters,
          decoration: const InputDecoration(hintText: 'PAVEX2609…'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Hủy')),
          FilledButton(onPressed: () => Navigator.pop(context, controller.text), child: const Text('Gửi')),
        ],
      ),
    );
    controller.dispose();
    final code = value == null ? null : extractCode(value);
    if (code != null) {
      await _handle(code);
    } else if (value != null && mounted) {
      showMessage(context, 'Mã không đúng định dạng PAVEX…', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final okCount = _entries.where((entry) => entry.ok).length;
    return Scaffold(
      appBar: AppBar(
        title: Text(scanActionLabel(widget.action)),
        actions: [
          IconButton(tooltip: 'Nhập mã', icon: const Icon(Icons.keyboard_outlined), onPressed: _typeCode),
          IconButton(tooltip: 'Đèn', icon: const Icon(Icons.flashlight_on_outlined), onPressed: _controller.toggleTorch),
          IconButton(tooltip: 'Đổi camera', icon: const Icon(Icons.cameraswitch_outlined), onPressed: _controller.switchCamera),
        ],
      ),
      body: Column(
        children: [
          AspectRatio(
            aspectRatio: 4 / 3,
            child: Stack(
              fit: StackFit.expand,
              children: [
                MobileScanner(
                  controller: _controller,
                  onDetect: _onDetect,
                  errorBuilder: (context, error) => Container(
                    color: Colors.black,
                    alignment: Alignment.center,
                    padding: const EdgeInsets.all(24),
                    child: const Text(
                      'Không mở được camera. Hãy cấp quyền camera cho ứng dụng hoặc nhập mã bằng tay.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white),
                    ),
                  ),
                ),
                IgnorePointer(
                  child: Center(
                    child: Container(
                      width: 240,
                      height: 240,
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.white, width: 3),
                        borderRadius: BorderRadius.circular(20),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (!_isLookup)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Row(
                children: [
                  Text('Đã quét ${_entries.length}', style: const TextStyle(fontWeight: FontWeight.w800)),
                  const Spacer(),
                  Text('$okCount thành công', style: const TextStyle(color: successGreen, fontWeight: FontWeight.w700)),
                ],
              ),
            ),
          Expanded(
            child: _entries.isEmpty
                ? EmptyState(
                    icon: Icons.qr_code_2,
                    title: 'Đưa mã QR trên nhãn kiện vào khung',
                    message: _isLookup ? 'Ứng dụng sẽ mở thông tin đơn.' : 'Mỗi mã được gửi ngay sau khi đọc.',
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                    itemCount: _entries.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (context, index) => _EntryTile(entry: _entries[index], onStart: _startAndRetry),
                  ),
          ),
        ],
      ),
    );
  }
}

class _EntryTile extends StatelessWidget {
  const _EntryTile({required this.entry, required this.onStart});

  final _ScanEntry entry;
  final Future<void> Function(_ScanEntry entry) onStart;

  @override
  Widget build(BuildContext context) {
    final color = entry.ok ? successGreen : Theme.of(context).colorScheme.error;
    final response = entry.response;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(entry.ok ? Icons.check_circle : Icons.error, color: color),
                const SizedBox(width: 8),
                Expanded(child: Text(entry.code, style: const TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.w800))),
                Text(timeOf(entry.at), style: TextStyle(color: Theme.of(context).colorScheme.outline)),
              ],
            ),
            if (entry.error != null) Padding(padding: const EdgeInsets.only(top: 6), child: Text(entry.error!)),
            if (response != null) ...[
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text('${response.shipment.recipient.contactName} · ${response.shipment.recipient.wardName}'),
              ),
              for (final result in response.results)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    '${result.parcelCode.split('-').last == result.parcelCode ? '' : 'Kiện ${result.parcelCode.split('-').last}: '}${result.message}',
                    style: TextStyle(color: result.ok ? null : Theme.of(context).colorScheme.error),
                  ),
                ),
              if (entry.startable != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: FilledButton.tonal(onPressed: () => onStart(entry), child: const Text('Bắt đầu việc này và quét lại')),
                ),
            ],
          ],
        ),
      ),
    );
  }
}
