import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pavex_warehouse/core/api.dart';
import 'package:pavex_warehouse/core/config.dart';
import 'package:pavex_warehouse/data/models.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Tokens implements TokenProvider {
  _Tokens(this.accessToken);

  @override
  String? accessToken;
  int refreshes = 0;

  @override
  Future<bool> refresh() async {
    refreshes += 1;
    accessToken = 'fresh';
    return true;
  }
}

MyShift _shift(DateTime start, DateTime end, {String status = 'SCHEDULED'}) => MyShift(
      shiftId: 's',
      name: 'Ca cả ngày',
      hubName: 'Bưu cục Ba Đình',
      startsAt: start,
      endsAt: end,
      assignmentStatus: status,
      checkedInAt: null,
      checkedOutAt: null,
    );

void main() {
  group('check-in window', () {
    final start = DateTime(2026, 10, 2, 7, 30);
    final end = DateTime(2026, 10, 2, 17, 30);

    test('opens 30 minutes before the shift and closes when it ends, as the server rules', () {
      final shift = _shift(start, end);
      expect(shift.checkInOpen(DateTime(2026, 10, 2, 6, 59)), isFalse);
      expect(shift.checkInOpen(DateTime(2026, 10, 2, 7, 0)), isTrue);
      expect(shift.checkInOpen(DateTime(2026, 10, 2, 17, 29)), isTrue);
      expect(shift.checkInOpen(end), isFalse);
      expect(shift.ended(end), isTrue);
    });

    test('a shift already checked in offers no check-in', () {
      expect(_shift(start, end, status: 'CHECKED_IN').checkInOpen(DateTime(2026, 10, 2, 9)), isFalse);
    });
  });

  group('api errors', () {
    late AppConfig config;

    setUp(() async {
      SharedPreferences.setMockInitialValues({'pavex.apiBaseUrl': 'http://localhost:8080'});
      config = await AppConfig.load();
    });

    test('a 403 from a token older than a role change is retried once with a fresh token', () async {
      final seen = <String?>[];
      final client = MockClient((request) async {
        seen.add(request.headers['authorization']);
        return request.headers['authorization'] == 'Bearer fresh'
            ? http.Response('[]', 200)
            : http.Response(jsonEncode({'code': 'forbidden', 'message': 'Forbidden'}), 403);
      });
      final tokens = _Tokens('stale');
      final api = ApiClient(config, client: client)..tokens = tokens;

      expect(await api.get('/api/v1/operations/assignments/mine'), isEmpty);
      expect(tokens.refreshes, 1);
      expect(seen, ['Bearer stale', 'Bearer fresh']);
    });

    test('backend codes read in Vietnamese', () async {
      final client = MockClient((_) async => http.Response(
            jsonEncode({'code': 'invalid_assignment_transition', 'message': 'Assignment must be ASSIGNED before this operation.'}),
            400,
          ));
      final api = ApiClient(config, client: client)..tokens = _Tokens('token');

      await expectLater(
        api.post('/api/v1/operations/assignments/a/accept'),
        throwsA(isA<ApiException>().having((error) => error.message, 'message', contains('đã được nhận hoặc đang làm'))),
      );
    });
  });
}
