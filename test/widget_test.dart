import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pavex_warehouse/app.dart';
import 'package:pavex_warehouse/core/api.dart';
import 'package:pavex_warehouse/core/config.dart';
import 'package:pavex_warehouse/core/format.dart';
import 'package:pavex_warehouse/core/ids.dart';
import 'package:pavex_warehouse/core/session.dart';
import 'package:pavex_warehouse/data/models.dart';
import 'package:pavex_warehouse/data/repository.dart';
import 'package:pavex_warehouse/ui/delivery_screen.dart';
import 'package:pavex_warehouse/ui/scan_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

String _token(Map<String, dynamic> claims) {
  String part(Map<String, dynamic> value) => base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
  return '${part({'alg': 'none'})}.${part(claims)}.signature';
}

WorkTask _deliveryTask() => WorkTask.fromJson({
      'assignmentId': 'a-1',
      'assignmentCode': 'ASG-1',
      'type': 'LAST_MILE_DELIVERY',
      'status': 'IN_PROGRESS',
      'hubId': 'h-1',
      'shipment': {
        'trackingCode': 'PAVEX2609250123456789',
        'status': 'OUT_FOR_DELIVERY',
        'serviceLevel': 'STANDARD',
        'sender': {'contactName': 'Shop', 'contactPhone': '0901234567', 'addressLine': '1 Lê Lợi', 'wardName': 'Hải Châu', 'provinceName': 'Đà Nẵng'},
        'recipient': {'contactName': 'Lan', 'contactPhone': '0912345678', 'addressLine': '2 Trần Phú', 'wardName': 'Bến Thành', 'provinceName': 'Hồ Chí Minh'},
        'amountToCollect': 250000,
        'codAmount': 228000,
        'collectionStatus': 'PENDING',
        'parcels': [
          {'parcelCode': 'PAVEX2609250123456789-01', 'sequence': 1, 'status': 'OUT_FOR_DELIVERY', 'description': 'Áo'},
          {'parcelCode': 'PAVEX2609250123456789-02', 'sequence': 2, 'status': 'AT_DESTINATION_HUB', 'description': 'Quần'},
        ],
      },
    });

void main() {
  group('scanned codes', () {
    test('a parcel code is read from a label or a tracking link', () {
      expect(extractCode('pavex2609250123456789-01'), 'PAVEX2609250123456789-01');
      expect(extractCode('https://pavex.vn/tracking?code=PAVEX2609250123456789'), 'PAVEX2609250123456789');
      expect(extractCode('8931234567890'), isNull);
    });
  });

  group('session', () {
    test('the most responsible hub role decides the app tabs', () {
      final manager = SessionUser.fromToken(_token({
        'sub': 'u-1',
        'email': 'truongbc@pavex.com',
        'roles': ['WAREHOUSE_OPERATOR', 'HUB_MANAGER'],
        'permissions': ['scans.create'],
      }));
      expect(manager.role, WorkRole.hubManager);
      expect(manager.role.worksAtHub, isTrue);
      expect(manager.can('scans.create'), isTrue);

      final driver = SessionUser.fromToken(_token({'sub': 'u-2', 'roles': ['LINE_HAUL_DRIVER']}));
      expect(driver.role, WorkRole.driver);
      expect(driver.role.handlesCash, isFalse);

      expect(SessionUser.fromToken(_token({'sub': 'u-3', 'roles': ['MERCHANT']})).role, WorkRole.unsupported);
    });
  });

  group('delivery', () {
    test('only parcels already out for delivery can be handed over', () {
      final target = DeliveryTarget.fromTask(_deliveryTask());
      expect(target.parcels.map((parcel) => parcel.code), ['PAVEX2609250123456789-01']);
      expect(target.parcels.single.assignmentId, 'a-1');
      expect(target.needsCollection, isTrue);
      expect(target.amountToCollect, 250000);
    });

    test('idempotency keys are distinct UUIDs', () {
      final keys = List.generate(50, (_) => newIdempotencyKey()).toSet();
      expect(keys, hasLength(50));
      expect(keys.first, matches(RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$')));
    });
  });

  group('formatting', () {
    test('money is shown in dong', () {
      expect(money(1250000), '1.250.000 ₫');
    });

    test('date ranges are inclusive calendar days', () {
      final range = DateRange.lastDays(7, DateTime(2026, 9, 25, 15));
      expect(range.from, DateTime(2026, 9, 19));
      expect(range.contains(DateTime(2026, 9, 25, 23, 59)), isTrue);
      expect(range.contains(DateTime(2026, 9, 18, 23, 59)), isFalse);
    });

    test('statuses read in Vietnamese', () {
      expect(statusLabel('DELIVERY_FAILED'), 'Giao thất bại');
      expect(taskTypeLabel('LINE_HAUL'), 'Chuyến trung chuyển');
    });
  });

  testWidgets('a signed-out worker sees the login form', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final config = await AppConfig.load();
    final session = SessionController(PavexRepository(ApiClient(config)));

    await tester.pumpWidget(PavexWarehouseApp(session: session, config: config));

    expect(find.text('Pavex Bưu cục'), findsOneWidget);
    expect(find.text('Đăng nhập'), findsOneWidget);
    expect(find.byType(TextFormField), findsNWidgets(2));
  });
}
