import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:signature/signature.dart';

import '../app.dart';
import '../core/format.dart';
import '../core/ids.dart';
import '../data/models.dart';
import 'theme.dart';
import 'widgets.dart';

class DeliveryParcel {
  const DeliveryParcel(this.code, this.assignmentId, this.description);

  final String code;
  final String assignmentId;
  final String description;
}

/// A shipment at the recipient's door, whichever list it was opened from.
class DeliveryTarget {
  DeliveryTarget({
    required this.trackingCode,
    required this.recipient,
    required this.amountToCollect,
    required this.needsCollection,
    required this.parcels,
    this.note,
  });

  factory DeliveryTarget.fromTask(WorkTask task) => DeliveryTarget(
        trackingCode: task.shipment.trackingCode,
        recipient: task.shipment.recipient,
        amountToCollect: task.shipment.amountToCollect,
        needsCollection: task.shipment.needsCollection,
        note: task.shipment.note,
        parcels: [
          for (final parcel in task.shipment.parcels)
            if (parcel.status == 'OUT_FOR_DELIVERY') DeliveryParcel(parcel.parcelCode, task.assignmentId, parcel.description),
        ],
      );

  factory DeliveryTarget.fromHeld(HeldDelivery delivery) => DeliveryTarget(
        trackingCode: delivery.trackingCode,
        recipient: delivery.recipient,
        amountToCollect: delivery.amountToCollect,
        needsCollection: delivery.needsCollection,
        note: delivery.note,
        parcels: [
          for (final parcel in delivery.parcels)
            if (parcel.status == 'OUT_FOR_DELIVERY' && parcel.assignmentId != null)
              DeliveryParcel(parcel.parcelCode, parcel.assignmentId!, parcel.description),
        ],
      );

  final String trackingCode;
  final Address recipient;
  final int amountToCollect;
  final bool needsCollection;
  final List<DeliveryParcel> parcels;
  final String? note;
}

enum _Proof { photo, signature }

class DeliveryScreen extends StatefulWidget {
  const DeliveryScreen({super.key, required this.target});

  final DeliveryTarget target;

  @override
  State<DeliveryScreen> createState() => _DeliveryScreenState();
}

class _DeliveryScreenState extends State<DeliveryScreen> {
  late final Set<String> _selected = widget.target.parcels.map((parcel) => parcel.code).toSet();
  late final _recipientName = TextEditingController(text: widget.target.recipient.contactName);
  final _note = TextEditingController();
  final _signature = SignatureController(penStrokeWidth: 3, exportBackgroundColor: Colors.white);

  /// One key per parcel and outcome, so retrying after a dropped connection records once.
  final _keys = <String, String>{};

  bool _delivered = true;
  bool _cashConfirmed = false;
  _Proof _proof = _Proof.photo;
  Uint8List? _photo;
  String? _evidenceReference;
  String? _failureReason;
  bool _busy = false;

  @override
  void dispose() {
    _recipientName.dispose();
    _note.dispose();
    _signature.dispose();
    super.dispose();
  }

  Future<void> _takePhoto() async {
    final file = await ImagePicker().pickImage(source: ImageSource.camera, maxWidth: 1600, imageQuality: 75);
    if (file == null) return;
    final bytes = await file.readAsBytes();
    setState(() {
      _photo = bytes;
      _evidenceReference = null;
    });
  }

  String? _validate() {
    if (_selected.isEmpty) return 'Chọn ít nhất một kiện.';
    if (_delivered) {
      if (widget.target.needsCollection && !_cashConfirmed) return 'Xác nhận đã thu đủ tiền trước khi hoàn tất.';
      if (_recipientName.text.trim().isEmpty) return 'Nhập tên người nhận hàng.';
      if (_proof == _Proof.photo && _photo == null) return 'Chụp ảnh bằng chứng giao hàng.';
      if (_proof == _Proof.signature && _signature.isEmpty) return 'Người nhận cần ký tên.';
    } else {
      if (_failureReason == null) return 'Chọn lý do giao thất bại.';
      if (_failureReason == 'OTHER' && _note.text.trim().isEmpty) return 'Ghi rõ lý do khác.';
    }
    return null;
  }

  Future<void> _submit() async {
    final problem = _validate();
    if (problem != null) {
      showMessage(context, problem, error: true);
      return;
    }
    if (!_delivered &&
        !await confirm(context, title: 'Báo giao thất bại?', message: deliveryFailureReasons[_failureReason]!, action: 'Báo thất bại')) {
      return;
    }
    if (!mounted) return;

    final repository = AppScope.repository(context);
    setState(() => _busy = true);
    try {
      if (_delivered && _evidenceReference == null) {
        final bytes = _proof == _Proof.photo ? _photo! : (await _signature.toPngBytes())!;
        _evidenceReference = await repository.uploadEvidence(bytes, _proof == _Proof.photo ? 'image/jpeg' : 'image/png');
      }
      var collectionPending = _delivered && widget.target.needsCollection;
      for (final parcel in widget.target.parcels.where((parcel) => _selected.contains(parcel.code))) {
        final key = _keys.putIfAbsent('${parcel.code}:$_delivered', newIdempotencyKey);
        await repository.recordAttempt(
          assignmentId: parcel.assignmentId,
          parcelCode: parcel.code,
          idempotencyKey: key,
          delivered: _delivered,
          failureReason: _delivered ? null : _failureReason,
          proofMethod: _delivered ? (_proof == _Proof.photo ? 'PHOTO' : 'SIGNATURE') : null,
          recipientName: _delivered ? _recipientName.text.trim() : null,
          evidenceReference: _delivered ? _evidenceReference : null,
          note: _note.text.trim().isEmpty ? null : _note.text.trim(),
          // The money is recorded once, with the first delivered parcel.
          collectedAmount: collectionPending ? widget.target.amountToCollect : null,
        );
        collectionPending = false;
      }
      if (!mounted) return;
      showMessage(context, _delivered ? 'Đã giao thành công.' : 'Đã ghi nhận giao thất bại.');
      Navigator.of(context).pop(true);
    } catch (error) {
      if (mounted) showMessage(context, errorText(error), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final target = widget.target;
    return Scaffold(
      appBar: AppBar(title: const Text('Giao hàng')),
      body: target.parcels.isEmpty
          ? const EmptyState(
              icon: Icons.inventory_2_outlined,
              title: 'Chưa có kiện nào đang đi giao',
              message: 'Quét “Xuất giao” các kiện trước khi hoàn tất giao hàng.',
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(target.trackingCode, style: const TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.w800)),
                        const SizedBox(height: 6),
                        Text(target.recipient.contactName, style: const TextStyle(fontWeight: FontWeight.w700)),
                        Text(target.recipient.full, style: TextStyle(color: Theme.of(context).colorScheme.outline)),
                        if (target.note != null) Text('Ghi chú: ${target.note}', style: const TextStyle(fontStyle: FontStyle.italic)),
                        const SizedBox(height: 10),
                        ContactActions(phone: target.recipient.contactPhone, address: target.recipient.full),
                      ],
                    ),
                  ),
                ),
                const SectionTitle('Kiện giao lần này'),
                Card(
                  child: Column(
                    children: [
                      for (final parcel in target.parcels)
                        CheckboxListTile(
                          value: _selected.contains(parcel.code),
                          onChanged: (value) => setState(() => value == true ? _selected.add(parcel.code) : _selected.remove(parcel.code)),
                          title: Text(parcel.code, style: const TextStyle(fontFamily: 'monospace')),
                          subtitle: Text(parcel.description),
                        ),
                    ],
                  ),
                ),
                const SectionTitle('Kết quả'),
                SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(value: true, icon: Icon(Icons.check_circle_outline), label: Text('Thành công')),
                    ButtonSegment(value: false, icon: Icon(Icons.cancel_outlined), label: Text('Thất bại')),
                  ],
                  selected: {_delivered},
                  onSelectionChanged: (value) => setState(() => _delivered = value.first),
                ),
                if (_delivered) ..._successFields(target) else ..._failureFields(),
              ],
            ),
      bottomNavigationBar: target.parcels.isEmpty
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: FilledButton(
                  onPressed: _busy ? null : _submit,
                  style: FilledButton.styleFrom(backgroundColor: _delivered ? successGreen : Theme.of(context).colorScheme.error),
                  child: _busy
                      ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                      : Text(_delivered ? 'Hoàn tất giao ${_selected.length} kiện' : 'Báo giao thất bại'),
                ),
              ),
            ),
    );
  }

  List<Widget> _successFields(DeliveryTarget target) => [
        if (target.needsCollection) ...[
          const SectionTitle('Thu tiền'),
          Card(
            color: warningAmber.withValues(alpha: 0.08),
            child: CheckboxListTile(
              value: _cashConfirmed,
              onChanged: (value) => setState(() => _cashConfirmed = value ?? false),
              title: Text('Đã thu đủ ${money(target.amountToCollect)}', style: const TextStyle(fontWeight: FontWeight.w800)),
              subtitle: const Text('Thu đúng số tiền này, không thu thiếu hay thừa.'),
            ),
          ),
        ],
        const SectionTitle('Người nhận'),
        TextField(controller: _recipientName, decoration: const InputDecoration(labelText: 'Tên người nhận hàng')),
        const SectionTitle('Bằng chứng giao hàng'),
        SegmentedButton<_Proof>(
          segments: const [
            ButtonSegment(value: _Proof.photo, icon: Icon(Icons.photo_camera_outlined), label: Text('Chụp ảnh')),
            ButtonSegment(value: _Proof.signature, icon: Icon(Icons.draw_outlined), label: Text('Chữ ký')),
          ],
          selected: {_proof},
          onSelectionChanged: (value) => setState(() {
            _proof = value.first;
            _evidenceReference = null;
          }),
        ),
        const SizedBox(height: 12),
        if (_proof == _Proof.photo)
          _photo == null
              ? OutlinedButton.icon(onPressed: _takePhoto, icon: const Icon(Icons.photo_camera), label: const Text('Chụp ảnh kiện đã giao'))
              : Column(
                  children: [
                    ClipRRect(borderRadius: BorderRadius.circular(12), child: Image.memory(_photo!, height: 220, fit: BoxFit.cover)),
                    TextButton.icon(onPressed: _takePhoto, icon: const Icon(Icons.refresh), label: const Text('Chụp lại')),
                  ],
                )
        else
          Column(
            children: [
              Container(
                decoration: BoxDecoration(border: Border.all(color: Theme.of(context).colorScheme.outlineVariant), borderRadius: BorderRadius.circular(12)),
                clipBehavior: Clip.antiAlias,
                child: Signature(controller: _signature, height: 200, backgroundColor: Colors.white),
              ),
              TextButton.icon(
                onPressed: () => setState(() {
                  _signature.clear();
                  _evidenceReference = null;
                }),
                icon: const Icon(Icons.clear),
                label: const Text('Ký lại'),
              ),
            ],
          ),
        const SizedBox(height: 12),
        TextField(controller: _note, maxLength: 500, decoration: const InputDecoration(labelText: 'Ghi chú (không bắt buộc)')),
      ];

  List<Widget> _failureFields() => [
        const SectionTitle('Lý do'),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final entry in deliveryFailureReasons.entries)
              ChoiceChip(
                label: Text(entry.value),
                selected: _failureReason == entry.key,
                onSelected: (_) => setState(() => _failureReason = entry.key),
              ),
          ],
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _note,
          maxLength: 500,
          decoration: const InputDecoration(labelText: 'Ghi chú', hintText: 'Ví dụ: hẹn giao lại sau 17h'),
        ),
        const Text('Kiện vẫn ở chỗ bạn để giao lại, hoặc mang về bưu cục khi đơn chuyển hoàn.'),
      ];
}
