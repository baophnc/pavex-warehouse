import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pavex_warehouse/app.dart';
import 'package:pavex_warehouse/core/api.dart';
import 'package:pavex_warehouse/core/config.dart';
import 'package:pavex_warehouse/core/session.dart';
import 'package:pavex_warehouse/data/repository.dart';
import 'package:pavex_warehouse/ui/config_error_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('release server address', () {
    test('must be an https:// address', () {
      expect(AppConfig.releaseBaseUrlError('https://api.pavex.vn'), isNull);
      expect(AppConfig.releaseBaseUrlError('https://api.pavex.vn:8443/gateway/'), isNull);

      expect(AppConfig.releaseBaseUrlError(''), contains('PAVEX_API_BASE_URL'));
      expect(AppConfig.releaseBaseUrlError('   '), contains('PAVEX_API_BASE_URL'));
      for (final bad in [
        'http://api.pavex.vn',
        'http://localhost:8080',
        'api.pavex.vn',
        'HTTPS//api.pavex.vn',
        'https://',
        'ftp://api.pavex.vn',
        'https://user:secret@api.pavex.vn',
        'https://api.pavex.vn?x=1',
      ]) {
        expect(AppConfig.releaseBaseUrlError(bad), contains('https://'), reason: bad);
      }
    });

    test('the web build may also use http://, the browser guards mixed content', () async {
      expect(AppConfig.releaseBaseUrlError('http://localhost:8080', web: true), isNull);
      expect(AppConfig.releaseBaseUrlError('https://api.pavex.vn', web: true), isNull);
      expect(AppConfig.releaseBaseUrlError('', web: true), contains('PAVEX_API_BASE_URL'));
      for (final bad in ['localhost:8080', 'ftp://api.pavex.vn', 'http://user:secret@api.pavex.vn', 'http://api.pavex.vn#x']) {
        expect(AppConfig.releaseBaseUrlError(bad, web: true), contains('http://'), reason: bad);
      }
      SharedPreferences.setMockInitialValues({});
      final config = await AppConfig.load(release: true, buildBaseUrl: 'http://localhost:8080/', web: true);
      expect(config.error, isNull);
      expect(config.baseUrl, 'http://localhost:8080');
      expect(config.editable, isFalse);
    });

    test('a release build uses only the build-time address, never a saved one', () async {
      SharedPreferences.setMockInitialValues({'pavex.apiBaseUrl': 'http://192.168.1.10:8080'});
      final config = await AppConfig.load(release: true, buildBaseUrl: 'https://api.pavex.vn/');

      expect(config.baseUrl, 'https://api.pavex.vn');
      expect(config.error, isNull);
      expect(config.editable, isFalse);
      expect(() => config.setBaseUrl('http://evil.example'), throwsStateError);
      expect(config.baseUrl, 'https://api.pavex.vn');
    });

    test('a release build without an HTTPS address reports an error', () async {
      SharedPreferences.setMockInitialValues({});
      expect((await AppConfig.load(release: true, buildBaseUrl: '')).error, isNotNull);
      expect((await AppConfig.load(release: true, buildBaseUrl: 'http://api.pavex.vn')).error, isNotNull);
    });

    test('debug and profile builds keep a saved address and stay editable', () async {
      SharedPreferences.setMockInitialValues({'pavex.apiBaseUrl': 'http://192.168.1.10:8080'});
      final config = await AppConfig.load(release: false, buildBaseUrl: '');

      expect(config.baseUrl, 'http://192.168.1.10:8080');
      expect(config.error, isNull);
      expect(config.editable, isTrue);
      await config.setBaseUrl('http://localhost:8080/');
      expect(config.baseUrl, 'http://localhost:8080');
    });
  });

  testWidgets('the release login screen has no server button', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final config = await AppConfig.load(release: true, buildBaseUrl: 'https://api.pavex.vn');
    final session = SessionController(PavexRepository(ApiClient(config)));

    await tester.pumpWidget(PavexWarehouseApp(session: session, config: config));

    expect(find.text('Đăng nhập'), findsOneWidget);
    expect(find.textContaining('Máy chủ:'), findsNothing);
    expect(find.byIcon(Icons.dns_outlined), findsNothing);
  });

  testWidgets('a release build without a server address explains why it cannot start', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final config = await AppConfig.load(release: true, buildBaseUrl: '');

    await tester.pumpWidget(ConfigErrorApp(message: config.error!));

    expect(find.text('Không thể kết nối máy chủ'), findsOneWidget);
    expect(find.textContaining('PAVEX_API_BASE_URL'), findsOneWidget);
  });
}
