import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Where the Pavex API gateway lives.
///
/// Debug and profile builds let anyone change it on the login screen, so the same build works on an
/// emulator, a simulator or a phone on the office Wi‑Fi. A release build only uses the address baked in
/// with `--dart-define=PAVEX_API_BASE_URL=https://…`, and refuses to start without a valid HTTPS one.
class AppConfig {
  AppConfig._(this._prefs, this._baseUrl, {required this.editable, this.error});

  static const _key = 'pavex.apiBaseUrl';

  final SharedPreferences _prefs;
  String _baseUrl;

  /// Whether the login screen may offer to change the server address (never in a release build).
  final bool editable;

  /// Why this build cannot reach a server, shown instead of the app; null when the address is usable.
  final String? error;

  String get baseUrl => _baseUrl;

  /// [release] and [buildBaseUrl] default to this build's values; tests pass their own.
  static Future<AppConfig> load({bool release = kReleaseMode, String buildBaseUrl = _buildBaseUrl}) async {
    final prefs = await SharedPreferences.getInstance();
    if (release) {
      return AppConfig._(prefs, normalize(buildBaseUrl), editable: false, error: releaseBaseUrlError(buildBaseUrl));
    }
    return AppConfig._(prefs, prefs.getString(_key) ?? defaultBaseUrl(buildBaseUrl), editable: true);
  }

  /// Set at build time: required for a release build, optional otherwise, e.g.
  /// `flutter run --dart-define=PAVEX_API_BASE_URL=http://localhost:8080` with `adb reverse`.
  static const _buildBaseUrl = String.fromEnvironment('PAVEX_API_BASE_URL');

  /// The message shown when a release build's server address is missing or not HTTPS; null when it is fine.
  static String? releaseBaseUrlError(String value) {
    final url = value.trim();
    if (url.isEmpty) {
      return 'Bản cài đặt này chưa được gắn địa chỉ máy chủ (PAVEX_API_BASE_URL). '
          'Hãy cài lại bản do bộ phận kỹ thuật Pavex cung cấp.';
    }
    final uri = Uri.tryParse(url);
    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty || uri.userInfo.isNotEmpty || uri.hasQuery || uri.hasFragment) {
      return 'Địa chỉ máy chủ của bản cài đặt này không hợp lệ: "$url". '
          'Bản phát hành chỉ kết nối qua https://. Hãy báo bộ phận kỹ thuật Pavex.';
    }
    return null;
  }

  static String normalize(String value) => value.trim().replaceAll(RegExp(r'/+$'), '');

  /// The Android emulator reaches the host machine through 10.0.2.2; a real phone does not.
  static String defaultBaseUrl([String buildBaseUrl = _buildBaseUrl]) {
    if (buildBaseUrl.isNotEmpty) return normalize(buildBaseUrl);
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      return 'http://10.0.2.2:8080';
    }
    return 'http://localhost:8080';
  }

  Future<void> setBaseUrl(String value) async {
    if (!editable) throw StateError('The server address is fixed in a release build.');
    final normalized = normalize(value);
    _baseUrl = normalized.isEmpty ? defaultBaseUrl() : normalized;
    await _prefs.setString(_key, _baseUrl);
  }
}
