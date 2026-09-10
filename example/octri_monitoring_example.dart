// A small HTTP server that reports its failures and times its work.
//
// Run it with:
//
//   dart run example/octri_monitoring_example.dart
//
// Then send a request to http://localhost:8080/orders, or to
// http://localhost:8080/boom to see an error reach the dashboard.

import 'dart:io';

import 'package:octri_monitoring/octri_monitoring.dart';

Future<void> main() async {
  // Point the reporter at your project. Hosted users can copy these three
  // values from the Monitoring connection settings in the dashboard.
  Octri.init(
    OctriConfig(
      url:
          Platform.environment['OCTRI_URL'] ?? 'https://monitoring.example.com',
      token: Platform.environment['OCTRI_TOKEN'],
      environment: Platform.environment['OCTRI_PROJECT'] ?? 'my-project-id',
      release: Platform.environment['GIT_SHA'],
    ),
  );

  // Send an event of your own. No generated API SDK is involved.
  Octri.captureEvent(
    'server.started',
    options: const OctriEventOptions(
      tags: <String, Object?>{'region': 'eu-west'},
    ),
  );

  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 8080);
  stdout.writeln('listening on http://localhost:8080');

  await for (final request in server) {
    // Continue the trace the caller started, so this server's spans and errors
    // join the client error for the same request.
    final trace = Octri.traceFromHeader(
      request.headers.value('traceparent'),
    );
    final startTime = DateTime.now();

    try {
      if (request.uri.path == '/boom') {
        throw StateError('the order could not be priced');
      }

      request.response.write('ok');
      await request.response.close();
    } catch (error, stackTrace) {
      Octri.captureError(
        error,
        stackTrace: stackTrace,
        options: OctriErrorOptions(
          method: request.method,
          path: request.uri.path,
          statusCode: 500,
          trace: trace,
        ),
      );

      request.response.statusCode = 500;
      await request.response.close();
    }

    // Time the request as one bar in the dashboard waterfall.
    Octri.captureSpan(
      OctriSpan(
        traceId: trace.traceId,
        spanId: trace.parentSpanId ?? 'a1b2c3d4e5f60718',
        name: '${request.method} ${request.uri.path}',
        startTime: startTime,
        endTime: DateTime.now(),
        status: request.response.statusCode >= 500 ? 'error' : 'ok',
      ),
    );
  }
}
