import 'dart:convert';
import 'dart:io';

import 'package:octri_monitoring/octri_monitoring.dart';
import 'package:test/test.dart';

void main() {
  test('parses W3C traceparent', () {
    final trace = Octri.traceFromHeader(
      '00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01',
    );
    expect(trace.traceId, '4bf92f3577b34da6a3ce929d0e0e4736');
    expect(trace.parentSpanId, '00f067aa0ba902b7');
  });

  test('rejects zero W3C trace and parent identifiers', () {
    final trace = Octri.traceFromHeader(
      '00-00000000000000000000000000000000-0000000000000000-01',
    );
    expect(trace.traceId, matches(RegExp(r'^[0-9a-f]{32}$')));
    expect(trace.traceId, isNot('00000000000000000000000000000000'));
    expect(trace.parentSpanId, isNull);
  });

  test('sends scoped auth and replaces an unsafe idempotency key', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    final received = server.first.timeout(const Duration(seconds: 3));

    Octri.init(OctriConfig(
      url: 'http://127.0.0.1:${server.port}/',
      token: 'project-token',
      environment: 'project-1',
    ));
    Octri.captureEvent(
      'checkout.completed',
      options: const OctriEventOptions(
        eventId: 'unsafe\r\nX-Injected: true',
        tags: <String, Object?>{'plan': 'growth'},
      ),
    );

    final request = await received;
    final body = jsonDecode(await utf8.decoder.bind(request).join())
        as Map<String, Object?>;
    final key = request.headers.value('idempotency-key');
    expect(key, matches(RegExp(r'^[0-9a-f]{32}$')));
    expect(request.headers.value('authorization'), 'Bearer project-token');
    expect(body['eventId'], key);
    expect(body['environment'], 'project-1');
    expect(body['message'], 'checkout.completed');
    request.response.statusCode = HttpStatus.accepted;
    await request.response.close();
  });
}
