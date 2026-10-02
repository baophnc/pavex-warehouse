// Wire models for the Pavex field app. Parsing is lenient: a missing optional
// field never crashes a screen, it just shows as empty.

DateTime? _date(dynamic value) => value is String ? DateTime.tryParse(value)?.toLocal() : null;

int _int(dynamic value) => value is num ? value.toInt() : int.tryParse('$value') ?? 0;

double _double(dynamic value) => value is num ? value.toDouble() : double.tryParse('$value') ?? 0;

String _str(dynamic value) => value?.toString() ?? '';

String? _opt(dynamic value) {
  final text = value?.toString();
  return text == null || text.isEmpty ? null : text;
}

List<T> _list<T>(dynamic value, T Function(Map<String, dynamic>) parse) =>
    value is List ? value.whereType<Map>().map((item) => parse(item.cast<String, dynamic>())).toList() : <T>[];

class AuthTokens {
  AuthTokens(this.accessToken, this.refreshToken, this.expiresIn, {this.passwordChangeRequired = false});

  factory AuthTokens.fromJson(Map<String, dynamic> json) => AuthTokens(
        _str(json['accessToken']),
        _str(json['refreshToken']),
        _int(json['expiresIn']),
        passwordChangeRequired: json['passwordChangeRequired'] == true,
      );

  final String accessToken;
  final String refreshToken;
  final int expiresIn;

  /// The account still has the temporary password an administrator issued.
  final bool passwordChangeRequired;
}

class Profile {
  Profile({required this.email, this.firstName, this.lastName, this.displayName});

  factory Profile.fromJson(Map<String, dynamic> json) => Profile(
        email: _str(json['email']),
        firstName: _opt(json['firstName']),
        lastName: _opt(json['lastName']),
        displayName: _opt(json['displayName']),
      );

  final String email;
  final String? firstName;
  final String? lastName;
  final String? displayName;

  String get name {
    final full = [lastName, firstName].whereType<String>().join(' ').trim();
    return displayName ?? (full.isEmpty ? email : full);
  }
}

class MyHub {
  MyHub({required this.id, required this.code, required this.name, required this.type, required this.primary});

  factory MyHub.fromJson(Map<String, dynamic> json) => MyHub(
        id: _str(json['id']),
        code: _str(json['code']),
        name: _str(json['name']),
        type: _str(json['type']),
        primary: json['primary'] == true,
      );

  final String id;
  final String code;
  final String name;
  final String type;
  final bool primary;
}

class HubScope {
  HubScope({required this.allHubs, required this.workforceKind, required this.hubs});

  factory HubScope.fromJson(Map<String, dynamic> json) => HubScope(
        allHubs: json['allHubs'] == true,
        workforceKind: _opt(json['workforceKind']),
        hubs: _list(json['hubs'], MyHub.fromJson),
      );

  final bool allHubs;
  final String? workforceKind;
  final List<MyHub> hubs;

  MyHub? get primary => hubs.isEmpty ? null : hubs.firstWhere((hub) => hub.primary, orElse: () => hubs.first);
}

class Address {
  Address({
    required this.contactName,
    required this.contactPhone,
    required this.addressLine,
    required this.wardName,
    required this.provinceName,
  });

  factory Address.fromJson(Map<String, dynamic> json) => Address(
        contactName: _str(json['contactName']),
        contactPhone: _str(json['contactPhone']),
        addressLine: _str(json['addressLine']),
        wardName: _str(json['wardName']),
        provinceName: _str(json['provinceName']),
      );

  final String contactName;
  final String contactPhone;
  final String addressLine;
  final String wardName;
  final String provinceName;

  String get full => [addressLine, wardName, provinceName].where((part) => part.isNotEmpty).join(', ');
}

class ParcelView {
  ParcelView({
    required this.parcelCode,
    required this.sequence,
    required this.status,
    required this.description,
    required this.isFragile,
    required this.weightKg,
    this.currentHubName,
  });

  factory ParcelView.fromJson(Map<String, dynamic> json) => ParcelView(
        parcelCode: _str(json['parcelCode'] ?? json['code']),
        sequence: _int(json['sequence']),
        status: _str(json['status']),
        description: _str(json['description']),
        isFragile: json['isFragile'] == true || json['fragile'] == true,
        weightKg: _double(json['chargeableWeightKg']),
        currentHubName: _opt(json['currentHubName']),
      );

  final String parcelCode;
  final int sequence;
  final String status;
  final String description;
  final bool isFragile;
  final double weightKg;
  final String? currentHubName;
}

class ShipmentView {
  ShipmentView({
    required this.trackingCode,
    required this.merchantReference,
    required this.status,
    required this.serviceLevel,
    required this.sender,
    required this.recipient,
    required this.originHubName,
    required this.destinationHubName,
    required this.amountToCollect,
    required this.codAmount,
    required this.collectionStatus,
    required this.note,
    required this.parcels,
  });

  factory ShipmentView.fromJson(Map<String, dynamic> json) => ShipmentView(
        trackingCode: _str(json['trackingCode']),
        merchantReference: _opt(json['merchantReference']),
        status: _str(json['status']),
        serviceLevel: _str(json['serviceLevel']),
        sender: Address.fromJson((json['sender'] as Map?)?.cast<String, dynamic>() ?? const {}),
        recipient: Address.fromJson((json['recipient'] as Map?)?.cast<String, dynamic>() ?? const {}),
        originHubName: _str(json['originHubName']),
        destinationHubName: _str(json['destinationHubName']),
        amountToCollect: _int(json['amountToCollect']),
        codAmount: _int(json['codAmount']),
        collectionStatus: _str(json['collectionStatus']),
        note: _opt(json['note']),
        parcels: _list(json['parcels'], ParcelView.fromJson),
      );

  final String trackingCode;
  final String? merchantReference;
  final String status;
  final String serviceLevel;
  final Address sender;
  final Address recipient;
  final String originHubName;
  final String destinationHubName;
  final int amountToCollect;
  final int codAmount;
  final String collectionStatus;
  final String? note;
  final List<ParcelView> parcels;

  bool get needsCollection => amountToCollect > 0 && collectionStatus == 'PENDING';
}

/// One open job of the signed-in worker.
class WorkTask {
  WorkTask({
    required this.assignmentId,
    required this.assignmentCode,
    required this.type,
    required this.status,
    required this.hubId,
    required this.hubName,
    required this.shipment,
    this.assignedAt,
    this.startedAt,
  });

  factory WorkTask.fromJson(Map<String, dynamic> json) => WorkTask(
        assignmentId: _str(json['assignmentId']),
        assignmentCode: _str(json['assignmentCode']),
        type: _str(json['type']),
        status: _str(json['status']),
        hubId: _str(json['hubId']),
        hubName: _opt(json['hubName']),
        shipment: ShipmentView.fromJson((json['shipment'] as Map).cast<String, dynamic>()),
        assignedAt: _date(json['assignedAt']),
        startedAt: _date(json['startedAt']),
      );

  final String assignmentId;
  final String assignmentCode;
  final String type;
  final String status;
  final String hubId;
  final String? hubName;
  final ShipmentView shipment;
  final DateTime? assignedAt;
  final DateTime? startedAt;

  bool get isPickup => type == 'PICKUP';
  bool get isDelivery => type == 'LAST_MILE_DELIVERY';
  bool get isLineHaul => type == 'LINE_HAUL';
  bool get isHubHandling => type.endsWith('_HUB_HANDLING');
  bool get awaitingAcceptance => status == 'ASSIGNED';
  bool get awaitingStart => status == 'ACCEPTED';
  bool get inProgress => status == 'IN_PROGRESS';

  /// The person the worker deals with for this job.
  Address get contact => isPickup ? shipment.sender : shipment.recipient;
}

class ScanResult {
  ScanResult({
    required this.parcelCode,
    required this.ok,
    required this.status,
    required this.code,
    required this.message,
    required this.assignmentId,
  });

  factory ScanResult.fromJson(Map<String, dynamic> json) => ScanResult(
        parcelCode: _str(json['parcelCode']),
        ok: json['ok'] == true,
        status: _str(json['status']),
        code: _opt(json['code']),
        message: _str(json['message']),
        assignmentId: _opt(json['assignmentId']),
      );

  final String parcelCode;
  final bool ok;
  final String status;
  final String? code;
  final String message;
  final String? assignmentId;
}

class ScanResponse {
  ScanResponse({required this.trackingCode, required this.results, required this.shipment});

  factory ScanResponse.fromJson(Map<String, dynamic> json) => ScanResponse(
        trackingCode: _str(json['trackingCode']),
        results: _list(json['results'], ScanResult.fromJson),
        shipment: ShipmentView.fromJson((json['shipment'] as Map).cast<String, dynamic>()),
      );

  final String trackingCode;
  final List<ScanResult> results;
  final ShipmentView shipment;
}

class TimelineEvent {
  TimelineEvent({required this.status, required this.description, required this.locationName, required this.occurredAt});

  factory TimelineEvent.fromJson(Map<String, dynamic> json) => TimelineEvent(
        status: _str(json['status']),
        description: _str(json['description']),
        locationName: _opt(json['locationName']),
        occurredAt: _date(json['occurredAt']),
      );

  final String status;
  final String description;
  final String? locationName;
  final DateTime? occurredAt;
}

class LookupResult {
  LookupResult({required this.shipment, required this.suggestedActions, required this.timeline});

  factory LookupResult.fromJson(Map<String, dynamic> json) => LookupResult(
        shipment: ShipmentView.fromJson((json['shipment'] as Map).cast<String, dynamic>()),
        suggestedActions: (json['suggestedActions'] as List? ?? const []).map((item) => '$item').toList(),
        timeline: _list(json['timeline'], TimelineEvent.fromJson),
      );

  final ShipmentView shipment;
  final List<String> suggestedActions;
  final List<TimelineEvent> timeline;
}

/// A shipment the courier is carrying right now (out for delivery or failed and not yet back).
class HeldDelivery {
  HeldDelivery({
    required this.trackingCode,
    required this.status,
    required this.recipient,
    required this.note,
    required this.amountToCollect,
    required this.collectionStatus,
    required this.parcels,
  });

  factory HeldDelivery.fromJson(Map<String, dynamic> json) => HeldDelivery(
        trackingCode: _str(json['trackingCode']),
        status: _str(json['status']),
        recipient: Address.fromJson((json['recipient'] as Map?)?.cast<String, dynamic>() ?? const {}),
        note: _opt(json['note']),
        amountToCollect: _int(json['amountToCollect']),
        collectionStatus: _str(json['collectionStatus']),
        parcels: _list(json['parcels'], HeldParcel.fromJson),
      );

  final String trackingCode;
  final String status;
  final Address recipient;
  final String? note;
  final int amountToCollect;
  final String collectionStatus;
  final List<HeldParcel> parcels;

  bool get needsCollection => amountToCollect > 0 && collectionStatus == 'PENDING';
}

class HeldParcel {
  HeldParcel({required this.parcelCode, required this.status, required this.description, required this.assignmentId});

  factory HeldParcel.fromJson(Map<String, dynamic> json) => HeldParcel(
        parcelCode: _str(json['parcelCode']),
        status: _str(json['status']),
        description: _str(json['description']),
        assignmentId: _opt(json['assignmentId']),
      );

  final String parcelCode;
  final String status;
  final String description;
  final String? assignmentId;
}

class CashCollection {
  CashCollection({
    required this.id,
    required this.trackingCode,
    required this.status,
    required this.amount,
    required this.codAmount,
    required this.feeAmount,
    required this.collectedAt,
    required this.currentHubId,
    required this.lastRejectionReason,
    required this.currentRemittanceId,
  });

  factory CashCollection.fromJson(Map<String, dynamic> json) => CashCollection(
        id: _str(json['id']),
        trackingCode: _str(json['trackingCode']),
        status: _str(json['status']),
        amount: _int(json['amount']),
        codAmount: _int(json['codAmount']),
        feeAmount: _int(json['feeAmount']),
        collectedAt: _date(json['collectedAt']),
        currentHubId: _opt(json['currentHubId']),
        lastRejectionReason: _opt(json['lastRejectionReason']),
        currentRemittanceId: _opt(json['currentRemittanceId']),
      );

  final String id;
  final String trackingCode;
  final String status;
  final int amount;
  final int codAmount;
  final int feeAmount;
  final DateTime? collectedAt;
  final String? currentHubId;
  final String? lastRejectionReason;
  final String? currentRemittanceId;
}

class CashRemittance {
  CashRemittance({
    required this.id,
    required this.remittanceNumber,
    required this.hubId,
    required this.status,
    required this.expectedAmount,
    required this.submittedAt,
    required this.approvedAt,
    required this.rejectionReason,
    required this.itemCount,
  });

  factory CashRemittance.fromJson(Map<String, dynamic> json) => CashRemittance(
        id: _str(json['id']),
        remittanceNumber: _str(json['remittanceNumber']),
        hubId: _str(json['hubId']),
        status: _str(json['status']),
        expectedAmount: _int(json['expectedAmount']),
        submittedAt: _date(json['submittedAt']),
        approvedAt: _date(json['approvedAt']),
        rejectionReason: _opt(json['rejectionReason']),
        itemCount: (json['items'] as List? ?? const []).length,
      );

  final String id;
  final String remittanceNumber;
  final String hubId;
  final String status;
  final int expectedAmount;
  final DateTime? submittedAt;
  final DateTime? approvedAt;
  final String? rejectionReason;
  final int itemCount;
}

class MyShift {
  MyShift({
    required this.shiftId,
    required this.name,
    required this.hubName,
    required this.startsAt,
    required this.endsAt,
    required this.assignmentStatus,
    required this.checkedInAt,
    required this.checkedOutAt,
  });

  factory MyShift.fromJson(Map<String, dynamic> json) => MyShift(
        shiftId: _str(json['shiftId']),
        name: _str(json['name']),
        hubName: _opt(json['hubName']),
        startsAt: _date(json['startsAt']),
        endsAt: _date(json['endsAt']),
        assignmentStatus: _str(json['assignmentStatus']),
        checkedInAt: _date(json['checkedInAt']),
        checkedOutAt: _date(json['checkedOutAt']),
      );

  final String shiftId;
  final String name;
  final String? hubName;
  final DateTime? startsAt;
  final DateTime? endsAt;
  final String assignmentStatus;
  final DateTime? checkedInAt;
  final DateTime? checkedOutAt;

  bool get canCheckIn => assignmentStatus == 'SCHEDULED';
  bool get canCheckOut => assignmentStatus == 'CHECKED_IN';

  /// Check-in opens 30 minutes before the start and closes when the shift ends (as the server rules).
  DateTime? get checkInOpensAt => startsAt?.subtract(const Duration(minutes: 30));

  bool checkInOpen(DateTime now) =>
      canCheckIn && checkInOpensAt != null && endsAt != null && !now.isBefore(checkInOpensAt!) && now.isBefore(endsAt!);

  bool ended(DateTime now) => endsAt != null && !now.isBefore(endsAt!);
}

class Availability {
  Availability({required this.status, required this.activeAssignments, required this.maxConcurrentAssignments});

  factory Availability.fromJson(Map<String, dynamic> json) => Availability(
        status: _str(json['status']),
        activeAssignments: _int(json['activeAssignments']),
        maxConcurrentAssignments: _int(json['maxConcurrentAssignments']),
      );

  final String status;
  final int activeAssignments;
  final int maxConcurrentAssignments;

  bool get available => status == 'AVAILABLE';
}

class ReportSummary {
  ReportSummary(this.values);

  /// Shown when the numbers could not be loaded; the rest of the screen still works.
  static final empty = ReportSummary(const {});

  factory ReportSummary.fromJson(Map<String, dynamic> json) =>
      ReportSummary({for (final entry in json.entries) if (entry.value is num) entry.key: (entry.value as num).toInt()});

  final Map<String, int> values;

  int operator [](String key) => values[key] ?? 0;
}

class ReportItem {
  ReportItem({
    required this.trackingCode,
    required this.status,
    required this.recipientName,
    required this.recipientPhone,
    required this.recipientAddress,
    required this.amountToCollect,
    required this.reason,
    required this.occurredAt,
  });

  factory ReportItem.fromJson(Map<String, dynamic> json) => ReportItem(
        trackingCode: _str(json['trackingCode']),
        status: _str(json['status']),
        recipientName: _str(json['recipientName']),
        recipientPhone: _str(json['recipientPhone']),
        recipientAddress: _str(json['recipientAddress']),
        amountToCollect: _int(json['amountToCollect']),
        reason: _opt(json['reason']),
        occurredAt: _date(json['occurredAt']),
      );

  final String trackingCode;
  final String status;
  final String recipientName;
  final String recipientPhone;
  final String recipientAddress;
  final int amountToCollect;
  final String? reason;
  final DateTime? occurredAt;
}

/// A line-haul departure of the driver: PLANNED (open work, not started), IN_PROGRESS or ARRIVED.
class DriverTrip {
  DriverTrip({
    required this.tripId,
    required this.status,
    required this.laneId,
    required this.laneCode,
    required this.fromHubCode,
    required this.fromHubName,
    required this.toHubCode,
    required this.toHubName,
    required this.plannedDepartureRaw,
    required this.plannedDepartureAt,
    required this.plannedArrivalAt,
    required this.distanceKm,
    required this.shipmentCount,
    required this.vehiclePlate,
    required this.startedAt,
    required this.arrivedAt,
  });

  factory DriverTrip.fromJson(Map<String, dynamic> json) {
    final from = (json['fromHub'] as Map?)?.cast<String, dynamic>() ?? const {};
    final to = (json['toHub'] as Map?)?.cast<String, dynamic>() ?? const {};
    return DriverTrip(
      tripId: _opt(json['tripId']),
      status: _str(json['status']),
      laneId: _str(json['laneId']),
      laneCode: _str(json['laneCode']),
      fromHubCode: _str(from['code']),
      fromHubName: _str(from['name']),
      toHubCode: _str(to['code']),
      toHubName: _str(to['name']),
      plannedDepartureRaw: _str(json['plannedDepartureAt']),
      plannedDepartureAt: _date(json['plannedDepartureAt']),
      plannedArrivalAt: _date(json['plannedArrivalAt']),
      distanceKm: json['distanceKm'] == null ? null : _double(json['distanceKm']),
      shipmentCount: _int(json['shipmentCount']),
      vehiclePlate: _opt(json['vehiclePlate']),
      startedAt: _date(json['startedAt']),
      arrivedAt: _date(json['arrivedAt']),
    );
  }

  final String? tripId;
  final String status;
  final String laneId;
  final String laneCode;
  final String fromHubCode;
  final String fromHubName;
  final String toHubCode;
  final String toHubName;

  /// Sent back unchanged when starting the trip, so it matches the server's instant exactly.
  final String plannedDepartureRaw;
  final DateTime? plannedDepartureAt;
  final DateTime? plannedArrivalAt;
  final double? distanceKm;
  final int shipmentCount;
  final String? vehiclePlate;
  final DateTime? startedAt;
  final DateTime? arrivedAt;

  bool get planned => status == 'PLANNED';
  bool get inProgress => status == 'IN_PROGRESS';
  bool get arrived => status == 'ARRIVED';
}

class FleetConsent {
  FleetConsent({required this.currentTermsVersion, required this.required});

  factory FleetConsent.fromJson(Map<String, dynamic> json) =>
      FleetConsent(currentTermsVersion: _str(json['currentTermsVersion']), required: json['required'] != false);

  final String currentTermsVersion;
  final bool required;
}

class LocationBatchResult {
  LocationBatchResult({required this.accepted, required this.tripStatus});

  factory LocationBatchResult.fromJson(Map<String, dynamic> json) =>
      LocationBatchResult(accepted: _int(json['accepted']), tripStatus: _str(json['tripStatus']));

  final int accepted;
  final String tripStatus;
}

/// One notice in the worker's inbox: a job given or taken back, an approval waiting, or a message.
class AppNotification {
  AppNotification({
    required this.id,
    required this.code,
    required this.severity,
    required this.title,
    required this.body,
    required this.isRead,
    required this.createdAt,
    required this.senderUserId,
  });

  factory AppNotification.fromJson(Map<String, dynamic> json) => AppNotification(
        id: _str(json['id']),
        code: _str(json['code']),
        severity: _str(json['severity']),
        title: _str(json['title']),
        body: _str(json['body']),
        isRead: json['isRead'] == true,
        createdAt: _date(json['createdAt']) ?? DateTime.now(),
        senderUserId: _opt(json['senderUserId']),
      );

  final String id;
  final String code;
  final String severity;
  final String title;
  final String body;
  final bool isRead;
  final DateTime createdAt;
  final String? senderUserId;

  /// A message a person wrote, rather than an automatic notice.
  bool get isMessage => senderUserId != null;

  AppNotification read() => AppNotification(
        id: id, code: code, severity: severity, title: title, body: body,
        isRead: true, createdAt: createdAt, senderUserId: senderUserId,
      );
}

class NotificationPage {
  NotificationPage({required this.items, required this.nextCursor, required this.unreadCount});

  factory NotificationPage.fromJson(Map<String, dynamic> json) => NotificationPage(
        items: _list(json['items'], AppNotification.fromJson),
        nextCursor: _opt(json['nextCursor']),
        unreadCount: _int(json['unreadCount']),
      );

  final List<AppNotification> items;
  final String? nextCursor;
  final int unreadCount;
}

/// What the signed-in worker may send: hub audiences at their hubs, and messages to shops.
class MessageOptions {
  MessageOptions({required this.hubIds, required this.audiences, required this.canMessageShops});

  factory MessageOptions.fromJson(Map<String, dynamic> json) => MessageOptions(
        hubIds: (json['hubIds'] as List? ?? const []).map((value) => '$value').toList(),
        audiences: (json['audiences'] as List? ?? const []).map((value) => '$value').toList(),
        canMessageShops: json['canMessageShops'] == true,
      );

  final List<String> hubIds;
  final List<String> audiences;
  final bool canMessageShops;

  static const audienceLabels = {
    'HUB_STAFF': 'Nhân viên bưu cục',
    'HUB_COURIERS': 'Bưu tá',
    'HUB_DRIVERS': 'Tài xế trung chuyển',
    'HUB_EVERYONE': 'Tất cả mọi người ở bưu cục',
  };
}
