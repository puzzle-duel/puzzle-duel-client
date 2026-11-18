import 'dart:convert';
import 'dart:io';

/// Authenticated Tournament UAT client. It never sends a score or a seal.
class UatApi {
  UatApi({required this.baseUrl, required this.bearer, this.sessionSecret});

  final String baseUrl;
  String bearer;
  String? sessionSecret;

  Future<UatHttpResult> get(String path) => _send('GET', path);

  Future<UatHttpResult> post(String path, [Object? body]) =>
      _send('POST', path, body);

  Future<UatHttpResult> _send(String method, String path, [Object? body]) async {
    final client = HttpClient();
    try {
      final request = await client
          .openUrl(method, Uri.parse('$baseUrl$path'))
          .timeout(const Duration(seconds: 8));
      request.headers.set(HttpHeaders.authorizationHeader, bearer);
      final secret = sessionSecret;
      if (secret != null) {
        request.headers.set('x-pzd-session-secret', secret);
      }
      if (body == null) {
        // Unknown length becomes Transfer-Encoding: chunked, which readBody rejects.
        request.contentLength = 0;
      } else {
        final bytes = utf8.encode(jsonEncode(body));
        request.headers.contentType = ContentType.json;
        request.contentLength = bytes.length;
        request.add(bytes);
      }
      final response = await request.close().timeout(const Duration(seconds: 12));
      final text = await utf8.decodeStream(response);
      Object? json;
      if (text.isNotEmpty) json = jsonDecode(text);
      return UatHttpResult(response.statusCode, json);
    } on SocketException {
      return const UatHttpResult(0, {'error': 'OFFLINE'});
    } on HttpException {
      return const UatHttpResult(0, {'error': 'OFFLINE'});
    } on Exception {
      return const UatHttpResult(0, {'error': 'TIMEOUT'});
    } finally {
      client.close(force: true);
    }
  }
}

final class UatHttpResult {
  const UatHttpResult(this.status, this.json);

  final int status;
  final Object? json;

  Map<String, Object?> get map {
    final value = json;
    if (value is Map) {
      return value.map((key, item) => MapEntry(key.toString(), item));
    }
    return const {};
  }

  String get error => map['error']?.toString() ?? 'REQUEST_FAILED';
}
