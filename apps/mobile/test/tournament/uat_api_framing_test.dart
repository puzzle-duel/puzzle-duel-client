import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:puzzle_duel_mobile/tournament/uat_api.dart';

/// Mirrors tournament `readBody`: chunked bodies and a length that does not
/// match the bytes are malformed. The server rule itself is not relaxed here.
bool _framedLikeTournamentReadBody(HttpRequest request, List<int> bytes) {
  if (request.headers.value(HttpHeaders.transferEncodingHeader) != null) {
    return false;
  }
  final header = request.headers.value(HttpHeaders.contentLengthHeader);
  if (header == null) return false;
  final length = int.tryParse(header);
  if (length == null || length < 0 || length > 16384) return false;
  return length == bytes.length && request.contentLength == length;
}

Future<HttpServer> _bind(List<HttpRequest> seen, List<List<int>> bodies) {
  return HttpServer.bind(InternetAddress.loopbackIPv4, 0).then((server) {
    server.listen((request) async {
      final bytes = await request.fold<List<int>>(
        <int>[],
        (previous, element) => previous..addAll(element),
      );
      seen.add(request);
      bodies.add(bytes);
      request.response.statusCode = 201;
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({'ok': true}));
      await request.response.close();
    });
    return server;
  });
}

void main() {
  test('401 responses carry unauthenticated category, not ok', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((request) async {
      request.response.statusCode = 401;
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({'error': 'UNAUTHENTICATED'}));
      await request.response.close();
    });
    final api = UatApi(
      baseUrl: 'http://127.0.0.1:${server.port}',
      bearer: 'Bearer uat-player-a',
    );
    final result = await api.post('/v1/tournament/session');
    expect(result.status, 401);
    expect(result.error, 'UNAUTHENTICATED');
    expect(result.category, UatFailureCategory.unauthenticated);
    expect(result.category, isNot(UatFailureCategory.ok));
  });

  test('nonempty JSON POST sends one UTF-8 body with Content-Length', () async {
    final seen = <HttpRequest>[];
    final bodies = <List<int>>[];
    final server = await _bind(seen, bodies);
    addTearDown(() => server.close(force: true));
    final api = UatApi(
      baseUrl: 'http://127.0.0.1:${server.port}',
      bearer: 'Bearer uat-player-a',
      sessionSecret: 'session-secret',
    );
    const payload = {
      'commandType': 'move',
      'idempotencyKey': 'tap-series-1-0-0-2-3',
      'move': {
        'offerIndex': 0,
        'tap': [2, 3],
        'expectedBoardRevision': 4,
        'writerGeneration': 1,
      },
    };

    final result = await api.post('/v1/tournament/series/series/commands', payload);

    expect(result.status, 201);
    final bytes = bodies.single;
    expect(utf8.decode(bytes), jsonEncode(payload));
    expect(seen.single.headers.value(HttpHeaders.contentTypeHeader), 'application/json; charset=utf-8');
    expect(seen.single.headers.value(HttpHeaders.authorizationHeader), 'Bearer uat-player-a');
    expect(seen.single.headers.value('x-pzd-session-secret'), 'session-secret');
    expect(_framedLikeTournamentReadBody(seen.single, bytes), isTrue);
  });

  test('zero-length POST is Content-Length 0 and not chunked', () async {
    final seen = <HttpRequest>[];
    final bodies = <List<int>>[];
    final server = await _bind(seen, bodies);
    addTearDown(() => server.close(force: true));
    final api = UatApi(
      baseUrl: 'http://127.0.0.1:${server.port}',
      bearer: 'Bearer uat-player-a',
    );

    final result = await api.post('/v1/tournament/session');

    expect(result.status, 201);
    expect(bodies.single, isEmpty);
    expect(seen.single.headers.value(HttpHeaders.contentTypeHeader), isNull);
    expect(seen.single.headers.value('x-pzd-session-secret'), isNull);
    expect(seen.single.headers.value(HttpHeaders.authorizationHeader), 'Bearer uat-player-a');
    expect(_framedLikeTournamentReadBody(seen.single, bodies.single), isTrue);
    expect(seen.single.contentLength, 0);
  });

  test('the same command bytes are resent without chunked framing', () async {
    final seen = <HttpRequest>[];
    final bodies = <List<int>>[];
    final server = await _bind(seen, bodies);
    addTearDown(() => server.close(force: true));
    final api = UatApi(
      baseUrl: 'http://127.0.0.1:${server.port}',
      bearer: 'Bearer uat-player-b',
      sessionSecret: 'session-secret',
    );
    const command = {
      'commandType': 'advance',
      'idempotencyKey': 'advance-series-1',
    };

    await api.post('/v1/tournament/series/series/commands', command);
    await api.post('/v1/tournament/series/series/commands', command);

    expect(bodies, hasLength(2));
    expect(bodies[0], bodies[1]);
    expect(utf8.decode(bodies[0]), jsonEncode(command));
    for (var i = 0; i < seen.length; i++) {
      expect(seen[i].headers.value(HttpHeaders.transferEncodingHeader), isNull);
      expect(_framedLikeTournamentReadBody(seen[i], bodies[i]), isTrue);
    }
  });
}
