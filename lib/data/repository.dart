import 'dart:typed_data';

import '../core/api.dart';
import '../core/format.dart';
import 'models.dart';

/// Every server call the field app makes, grouped by feature.
class PavexRepository {
  PavexRepository(this.api);

  final ApiClient api;

  // Account.

  Future<AuthTokens> login(String email, String password) async => AuthTokens.fromJson(
        await api.postAnonymous('/api/v1/auth/login', {'email': email.trim().toLowerCase(), 'password': password}),
      );

  Future<AuthTokens> refresh(String refreshToken) async =>
      AuthTokens.fromJson(await api.postAnonymous('/api/v1/auth/refresh', {'refreshToken': refreshToken}));

  Future<void> logout(String refreshToken) => api.post('/api/v1/auth/logout', body: {'refreshToken': refreshToken});

  /// Ends every session of the account, so the caller signs in again with the new password.
  Future<void> changePassword(String currentPassword, String newPassword) =>
      api.post('/api/v1/auth/change-password', body: {'currentPassword': currentPassword, 'newPassword': newPassword});

  /// Emails a reset link; the answer is the same whether or not the email exists.
  Future<void> forgotPassword(String email) =>
      api.postAnonymous('/api/v1/auth/forgot-password', {'email': email.trim().toLowerCase(), 'portal': 'MANAGEMENT'});

  Future<void> resetPassword(String token, String newPassword) =>
      api.postAnonymous('/api/v1/auth/reset-password', {'token': token, 'newPassword': newPassword});

  Future<Profile> me() async => Profile.fromJson(await api.get('/api/v1/auth/me'));

  Future<HubScope> hubScope() async => HubScope.fromJson(await api.get('/api/v1/operations/me/hub-scope'));

  // Jobs.

  Future<List<WorkTask>> tasks() async =>
      ((await api.get('/api/v1/workforce/tasks')) as List).map((item) => WorkTask.fromJson((item as Map).cast())).toList();

  Future<void> acceptTask(String id) => api.post('/api/v1/operations/assignments/$id/accept');

  Future<void> startTask(String id) => api.post('/api/v1/operations/assignments/$id/start');

  Future<void> rejectTask(String id, String reason) =>
      api.post('/api/v1/operations/assignments/$id/reject', body: {'reason': reason});

  Future<Availability> availability() async => Availability.fromJson(await api.get('/api/v1/operations/availability'));

  Future<Availability> setAvailability(bool available) async => Availability.fromJson(
        await api.put('/api/v1/operations/availability', body: {'status': available ? 'AVAILABLE' : 'UNAVAILABLE'}),
      );

  Future<List<MyShift>> shifts(DateTime from, DateTime to) async => ((await api.get(
        '/api/v1/operations/shifts/mine',
        query: {'from': from.toUtc().toIso8601String(), 'to': to.toUtc().toIso8601String()},
      )) as List)
          .map((item) => MyShift.fromJson((item as Map).cast()))
          .toList();

  Future<void> checkIn(String shiftId) => api.post('/api/v1/operations/shifts/$shiftId/check-in');

  Future<void> checkOut(String shiftId) => api.post('/api/v1/operations/shifts/$shiftId/check-out');

  // Scanning.

  Future<LookupResult> lookup(String code) async =>
      LookupResult.fromJson(await api.get('/api/v1/workforce/lookup/${Uri.encodeComponent(code.trim().toUpperCase())}'));

  Future<ScanResponse> scan(String code, String action, {String? hubId}) async => ScanResponse.fromJson(
        await api.post('/api/v1/workforce/scans', body: {'code': code.trim().toUpperCase(), 'action': action, 'hubId': hubId}),
      );

  // Delivery.

  Future<List<HeldDelivery>> heldDeliveries() async => ((await api.get('/api/v1/deliveries/mine')) as List)
      .map((item) => HeldDelivery.fromJson((item as Map).cast()))
      .toList();

  /// Returns the reference to cite as delivery evidence.
  Future<String> uploadEvidence(Uint8List bytes, String contentType) async {
    final extension = contentType.endsWith('png') ? 'png' : 'jpg';
    final response = await api.upload('/api/v1/workforce/evidence', bytes, filename: 'bang-chung.$extension', contentType: contentType);
    return (response as Map)['reference'].toString();
  }

  Future<void> recordAttempt({
    required String assignmentId,
    required String parcelCode,
    required String idempotencyKey,
    required bool delivered,
    String? failureReason,
    String? proofMethod,
    String? recipientName,
    String? evidenceReference,
    String? note,
    int? collectedAmount,
  }) =>
      api.post('/api/v1/deliveries/attempts', body: {
        'assignmentId': assignmentId,
        'parcelCode': parcelCode,
        'idempotencyKey': idempotencyKey,
        'outcome': delivered ? 'DELIVERED' : 'FAILED',
        'failureReason': failureReason,
        'proofMethod': proofMethod,
        'recipientName': recipientName,
        'evidenceReference': evidenceReference,
        'note': note,
        'collectedAmount': collectedAmount,
      });

  // Cash.

  Future<List<CashCollection>> myCollections({String? status}) async =>
      ((await api.get('/api/v1/billing/cash/collections/mine', query: {'status': status})) as List)
          .map((item) => CashCollection.fromJson((item as Map).cast()))
          .toList();

  Future<List<CashRemittance>> myRemittances() async => ((await api.get('/api/v1/billing/cash/remittances/mine')) as List)
      .map((item) => CashRemittance.fromJson((item as Map).cast()))
      .toList();

  Future<CashRemittance> submitRemittance(String hubId, List<CashCollection> collections) async =>
      CashRemittance.fromJson(await api.post('/api/v1/billing/cash/remittances', body: {
        'hubId': hubId,
        'collectionIds': collections.map((item) => item.id).toList(),
        'declaredAmount': collections.fold<int>(0, (sum, item) => sum + item.amount),
      }));

  Future<List<CashCollection>> hubCollections(String hubId, {String? status}) async =>
      ((await api.get('/api/v1/billing/cash/hubs/$hubId/collections', query: {'status': status})) as List)
          .map((item) => CashCollection.fromJson((item as Map).cast()))
          .toList();

  Future<void> resubmitCollection(String collectionId) =>
      api.post('/api/v1/billing/cash/collections/$collectionId/resubmit');

  // Line-haul trips (drivers).

  Future<FleetConsent> fleetConsent() async => FleetConsent.fromJson(await api.get('/api/v1/fleet/me/consent'));

  Future<FleetConsent> acceptFleetConsent(String termsVersion) async =>
      FleetConsent.fromJson(await api.put('/api/v1/fleet/me/consent', body: {'termsVersion': termsVersion}));

  Future<List<DriverTrip>> myTrips() async => ((await api.get('/api/v1/fleet/me/trips')) as List)
      .map((item) => DriverTrip.fromJson((item as Map).cast()))
      .toList();

  Future<DriverTrip> startTrip(DriverTrip trip, {String? vehiclePlate}) async => DriverTrip.fromJson(
        await api.post('/api/v1/fleet/me/trips/start', body: {
          'laneId': trip.laneId,
          'plannedDepartureAt': trip.plannedDepartureRaw,
          'vehiclePlate': vehiclePlate,
        }),
      );

  /// Starts the trip being loaded after a successful "load onto truck" scan; null when none is.
  Future<DriverTrip?> startTripFromScan() async {
    final response = await api.post('/api/v1/fleet/me/trips/start-from-scan');
    return response is Map ? DriverTrip.fromJson(response.cast()) : null;
  }

  Future<DriverTrip> arriveTrip(String tripId) async =>
      DriverTrip.fromJson(await api.post('/api/v1/fleet/me/trips/$tripId/arrive'));

  Future<LocationBatchResult> sendLocations(String tripId, List<Map<String, dynamic>> points) async =>
      LocationBatchResult.fromJson(await api.post('/api/v1/fleet/me/trips/$tripId/locations', body: {'points': points}));

  // Reports.

  Future<ReportSummary> reportSummary(DateRange range, {String? hubId}) async => ReportSummary.fromJson(
        await api.get('/api/v1/workforce/reports/summary', query: {
          'from': isoDate(range.from),
          'to': isoDate(range.to),
          'hubId': hubId,
        }),
      );

  Future<List<ReportItem>> reportItems(String kind, DateRange range, {String? hubId}) async =>
      ((await api.get('/api/v1/workforce/reports/items', query: {
        'kind': kind,
        'from': isoDate(range.from),
        'to': isoDate(range.to),
        'hubId': hubId,
      })) as List)
          .map((item) => ReportItem.fromJson((item as Map).cast()))
          .toList();
}
