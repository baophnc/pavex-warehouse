import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart' show MediaType;

import 'config.dart';

/// A request the server refused, with the reason in plain Vietnamese when possible.
class ApiException implements Exception {
  ApiException(this.status, this.code, this.message);

  final int status;
  final String code;
  final String message;

  bool get unauthorized => status == 401;

  @override
  String toString() => message;
}

/// Supplies and renews the bearer token; implemented by the session.
abstract class TokenProvider {
  String? get accessToken;

  /// Returns true when a fresh access token is now available.
  Future<bool> refresh();
}

class ApiClient {
  ApiClient(this.config, {http.Client? client}) : _http = client ?? http.Client();

  final AppConfig config;
  final http.Client _http;
  TokenProvider? tokens;

  static const _timeout = Duration(seconds: 20);

  Future<dynamic> get(String path, {Map<String, String?>? query}) =>
      _send('GET', path, query: query);

  Future<dynamic> post(String path, {Object? body}) => _send('POST', path, body: body);

  Future<dynamic> put(String path, {Object? body}) => _send('PUT', path, body: body);

  /// Calls that must not carry (or refresh) a user token, such as login.
  Future<dynamic> postAnonymous(String path, Object body) =>
      _send('POST', path, body: body, authenticated: false);

  Future<dynamic> upload(String path, Uint8List bytes, {required String filename, required String contentType}) async {
    Future<http.StreamedResponse> send() {
      final request = http.MultipartRequest('POST', _uri(path, null));
      _authorize(request.headers);
      request.files.add(http.MultipartFile.fromBytes('file', bytes, filename: filename, contentType: MediaType.parse(contentType)));
      return _http.send(request).timeout(const Duration(seconds: 60));
    }

    var streamed = await _guard(send);
    if (streamed.statusCode == 401 && await (tokens?.refresh() ?? Future.value(false))) {
      streamed = await _guard(send);
    }
    return _decode(await http.Response.fromStream(streamed));
  }

  Future<dynamic> _send(
    String method,
    String path, {
    Map<String, String?>? query,
    Object? body,
    bool authenticated = true,
  }) async {
    Future<http.Response> send() {
      final request = http.Request(method, _uri(path, query));
      request.headers['accept'] = 'application/json';
      if (authenticated) _authorize(request.headers);
      if (body != null) {
        request.headers['content-type'] = 'application/json';
        request.body = jsonEncode(body);
      }
      return _guard(() => _http.send(request).timeout(_timeout)).then(http.Response.fromStream);
    }

    var response = await send();
    if (authenticated && response.statusCode == 401 && await (tokens?.refresh() ?? Future.value(false))) {
      response = await send();
    }
    return _decode(response);
  }

  Uri _uri(String path, Map<String, String?>? query) {
    final base = Uri.parse(config.baseUrl);
    final params = <String, String>{
      for (final entry in (query ?? const {}).entries)
        if (entry.value != null && entry.value!.isNotEmpty) entry.key: entry.value!,
    };
    return base.replace(path: '${base.path}$path', queryParameters: params.isEmpty ? null : params);
  }

  void _authorize(Map<String, String> headers) {
    final token = tokens?.accessToken;
    if (token != null) headers['authorization'] = 'Bearer $token';
  }

  Future<T> _guard<T>(Future<T> Function() call) async {
    try {
      return await call();
    } on TimeoutException {
      throw ApiException(0, 'timeout', 'Máy chủ phản hồi quá lâu. Kiểm tra mạng rồi thử lại.');
    } on http.ClientException {
      throw ApiException(0, 'network', 'Không kết nối được máy chủ ${config.baseUrl}.');
    }
  }

  dynamic _decode(http.Response response) {
    final text = utf8.decode(response.bodyBytes);
    dynamic data;
    if (text.isNotEmpty) {
      try {
        data = jsonDecode(text);
      } on FormatException {
        data = null;
      }
    }
    if (response.statusCode >= 200 && response.statusCode < 300) return data;

    final error = data is Map ? (data['error'] is Map ? data['error'] as Map : data) : const {};
    final code = error['code']?.toString() ?? 'http_${response.statusCode}';
    final message = error['message']?.toString();
    throw ApiException(response.statusCode, code, _friendly(response.statusCode, message));
  }

  static String _friendly(int status, String? message) {
    if (status == 401) return 'Phiên đăng nhập đã hết hạn. Vui lòng đăng nhập lại.';
    if (status == 403) return message != null && _looksVietnamese(message) ? message : 'Bạn không có quyền thực hiện thao tác này.';
    if (status == 429) return 'Bạn thao tác quá nhanh. Vui lòng chờ một chút.';
    if (status >= 500) return 'Hệ thống đang bận. Vui lòng thử lại sau.';
    return message ?? 'Yêu cầu không hợp lệ.';
  }

  static bool _looksVietnamese(String text) => RegExp(r'[àáảãạăâđèéêìíòóôơùúưỳý]', caseSensitive: false).hasMatch(text);
}
