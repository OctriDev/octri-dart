import 'dart:convert';
import 'dart:io';

import 'package:octri_monitoring/octri_monitoring.dart';
import 'package:test/test.dart';

/// Starts an ingest stub, points the reporter at it, and returns the payload
/// the next capture posts.
Future<Map<String, Object?>> capture(void Function() emit) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  addTearDown(() => server.close(force: true));
  final received = server.first.timeout(const Duration(seconds: 3));

  Octri.init(OctriConfig(
    url: 'http://127.0.0.1:${server.port}/',
    environment: 'project-1',
  ));
  emit();

  final request = await received;
  final body =
      jsonDecode(await utf8.decoder.bind(request).join()) as Map<String, Object?>;
  request.response.statusCode = HttpStatus.accepted;
  await request.response.close();
  return body;
}

Future<Map<String, Object?>> captureEvent(
  String message, {
  OctriEventOptions options = const OctriEventOptions(),
}) =>
    capture(() => Octri.captureEvent(message, options: options));

void main() {
  tearDown(() => Octri.setBeforeSend(null));

  group('keys', () {
    test('credential-shaped keys are redacted however they are spelled',
        () async {
      final payload = await captureEvent(
        'checkout failed',
        options: const OctriEventOptions(context: <String, Object?>{
          'api_key': 'sk_live_1',
          'apiKey': 'sk_live_2',
          'X-API-KEY': 'sk_live_3',
          'stripeSecretKey': 'sk_live_4',
          'Authorization': 'Bearer abc',
          'refresh_token': 'rt_1',
          'cookie': 'sid=1',
          'orderId': 'A-1024',
          'author': 'ada',
        }),
      );

      final context = payload['context']! as Map<String, Object?>;
      for (final key in [
        'api_key',
        'apiKey',
        'X-API-KEY',
        'stripeSecretKey',
        'Authorization',
        'refresh_token',
        'cookie',
      ]) {
        expect(context[key], '[redacted]', reason: key);
      }
      expect(context['orderId'], 'A-1024');
      expect(context['author'], 'ada');
    });

    test('nested and list values are redacted too', () async {
      final payload = await captureEvent(
        'upstream rejected the call',
        options: const OctriEventOptions(context: <String, Object?>{
          'upstream': <String, Object?>{
            'headers': [
              <String, Object?>{'authorization': 'Bearer abc'},
            ],
          },
        }),
      );

      final context = payload['context']! as Map<String, Object?>;
      final upstream = context['upstream']! as Map<String, Object?>;
      final headers = upstream['headers']! as List<Object?>;
      expect((headers.first! as Map<String, Object?>)['authorization'],
          '[redacted]');
    });

    test('addScrubFields is additive', () async {
      Octri.addScrubFields(['accountNumber']);
      final payload = await captureEvent(
        'payout failed',
        options: const OctriEventOptions(context: <String, Object?>{
          'accountNumber': '12345678',
          'orderId': 'A-1024',
        }),
      );

      final context = payload['context']! as Map<String, Object?>;
      expect(context['accountNumber'], '[redacted]');
      expect(context['orderId'], 'A-1024');
    });
  });

  group('free text', () {
    test('a bearer token in a message is stripped', () async {
      final payload = await captureEvent(
        '401 from billing: Authorization: Bearer sk_live_abc123 rejected',
      );

      expect(payload['message'], isNot(contains('sk_live_abc123')));
      expect(payload['message'], contains('[redacted]'));
    });

    test('a JWT in a message is stripped', () async {
      final payload = await captureEvent(
        'token eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxIn0.7Hk2 expired',
      );

      expect(payload['message'], 'token [redacted] expired');
    });

    test('an email in a message is stripped', () async {
      final payload = await captureEvent('no account for ada@example.com');

      expect(payload['message'], 'no account for [redacted]');
    });

    test('a card number is stripped but an order number is not', () async {
      final payload = await captureEvent(
        'charge 4242 4242 4242 4242 failed for order 1234567890123',
      );

      expect(payload['message'], isNot(contains('4242')));
      expect(payload['message'], contains('1234567890123'));
    });
  });

  test('user identity survives but user credentials do not', () async {
    final payload = await captureEvent(
      'profile update failed',
      options: const OctriEventOptions(user: <String, Object?>{
        'id': 'u_1',
        'email': 'ada@example.com',
        'sessionToken': 'st_1',
      }),
    );

    final user = payload['user']! as Map<String, Object?>;
    expect(user['email'], 'ada@example.com');
    expect(user['id'], 'u_1');
    expect(user['sessionToken'], '[redacted]');
  });

  group('setBeforeSend', () {
    test('can edit a payload, and redaction still runs after it', () async {
      Octri.setBeforeSend((payload) {
        payload['context'] = <String, Object?>{'note': 'call ada@example.com'};
        return payload;
      });

      final payload = await captureEvent('build failed');
      final context = payload['context']! as Map<String, Object?>;
      expect(context['note'], 'call [redacted]');
    });

    test('returning null drops the event', () async {
      Octri.setBeforeSend(
        (payload) => payload['message'] == 'noise' ? null : payload,
      );

      final payload = await capture(() {
        Octri.captureEvent('noise');
        Octri.captureEvent('signal');
      });
      expect(payload['message'], 'signal');
    });
  });
}
