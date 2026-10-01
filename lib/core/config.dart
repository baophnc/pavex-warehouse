import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Where the Pavex API gateway lives. Editable on the login screen so the same
/// build works on an emulator, a simulator or a phone on the office Wi‑Fi.
class AppConfig {
  AppConfig._(this._prefs, this._baseUrl);

  static const _key = 'pavex.apiBaseUrl';

  final SharedPreferences _prefs;
  String _baseUrl;

  String get baseUrl => _baseUrl;

  static Future<AppConfig> load() async {
    final prefs = await SharedPreferences.getInstance();
    return AppConfig._(prefs, prefs.getString(_key) ?? defaultBaseUrl());
  }

  /// Set at build time for a real phone, e.g.
  /// `flutter run --dart-define=PAVEX_API_BASE_URL=http://localhost:8080` with `adb reverse`.
  static const _buildBaseUrl = String.fromEnvironment('PAVEX_API_BASE_URL');

  /// The Android emulator reaches the host machine through 10.0.2.2; a real phone does not.
  static String defaultBaseUrl() {
    if (_buildBaseUrl.isNotEmpty) return _buildBaseUrl;
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      return 'http://10.0.2.2:8080';
    }
    return 'http://localhost:8080';
  }

  Future<void> setBaseUrl(String value) async {
    final normalized = value.trim().replaceAll(RegExp(r'/+$'), '');
    _baseUrl = normalized.isEmpty ? defaultBaseUrl() : normalized;
    await _prefs.setString(_key, _baseUrl);
  }
}
