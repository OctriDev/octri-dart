import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

class OctriConfig {
  OctriConfig({
    required String url,
    this.token,
    required this.environment,
    this.release,
  }) : url = url.replaceFirst(RegExp(r'/+$'), '');

  final String url;

  /// Optional only for open self-hosted ingestion. Hosted Octri requires it.
  final String? token;
  final String environment;
  final String? release;
}

class OctriTraceContext {
  const OctriTraceContext(this.traceId, [this.parentSpanId]);

  final String traceId;
  final String? parentSpanId;
}

class OctriEventOptions {
  const OctriEventOptions({
    this.timestamp,
    this.level = 'info',
    this.operationId,
    this.method,
    this.path,
    this.statusCode,
    this.latencyMs,
    this.attempt,
    this.requestId,
    this.user,
    this.tags,
    this.context,
    this.breadcrumbs,
    this.fingerprint,
    this.trace,
    this.spanId,
    this.eventId,
  });

  final DateTime? timestamp;
  final String level;
  final String? operationId;
  final String? method;
  final String? path;
  final int? statusCode;
  final num? latencyMs;
  final int? attempt;
  final String? requestId;
  final Map<String, Object?>? user;
  final Map<String, Object?>? tags;
  final Map<String, Object?>? context;
  final List<Map<String, Object?>>? breadcrumbs;
  final String? fingerprint;
  final OctriTraceContext? trace;
  final String? spanId;
  final String? eventId;
}

class OctriErrorOptions {
  const OctriErrorOptions({
    this.level = 'error',
    this.operationId,
    this.method,
    this.path,
    this.statusCode,
    this.trace,
  });

  final String level;
  final String? operationId;
  final String? method;
  final String? path;
  final int? statusCode;
  final OctriTraceContext? trace;
}

class OctriSpan {
  const OctriSpan({
    required this.traceId,
    required this.spanId,
    this.parentSpanId,
    required this.name,
    this.service = 'server',
    this.operationId,
    required this.startTime,
    this.endTime,
    this.status = 'ok',
  });

  final String traceId;
  final String spanId;
  final String? parentSpanId;
  final String name;
  final String service;
  final String? operationId;
  final DateTime startTime;
  final DateTime? endTime;
  final String status;
}

/// Standalone Octri monitoring for Dart VM applications.
///
/// Delivery is asynchronous and best-effort. Transport failures are suppressed
/// so telemetry cannot affect the host application.
abstract final class Octri {
  static OctriConfig? _config;
  static final Random _random = Random.secure();
  static final RegExp _traceparent = RegExp(
    r'^00-([0-9a-f]{32})-([0-9a-f]{16})-[0-9a-f]{2}$',
    caseSensitive: false,
  );

  static void init(OctriConfig config) {
    _config = config;
  }

  static OctriTraceContext traceFromHeader(String? traceparent) {
    final match = traceparent == null
        ? null
        : _traceparent.firstMatch(traceparent.trim());
    if (match != null &&
        !_allZeros(match.group(1)!) &&
        !_allZeros(match.group(2)!)) {
      return OctriTraceContext(
        match.group(1)!.toLowerCase(),
        match.group(2)!.toLowerCase(),
      );
    }
    return OctriTraceContext(_randomHex(16));
  }

  /// Log an event without depending on a generated Octri API SDK.
  static void captureEvent(
    String message, {
    OctriEventOptions options = const OctriEventOptions(),
  }) {
    final config = _config;
    if (config == null) return;
    final requestedEventId = options.eventId;
    final eventId = requestedEventId != null && _safeHeaderValue(requestedEventId)
        ? requestedEventId
        : _randomHex(16);
    final payload = _compact(<String, Object?>{
      'eventId': eventId,
      'timestamp':
          (options.timestamp ?? DateTime.now()).toUtc().toIso8601String(),
      'level': options.level,
      'message': message,
      'operationId': options.operationId,
      'method': options.method,
      'path': options.path,
      'statusCode': options.statusCode,
      'latencyMs': options.latencyMs,
      'attempt': options.attempt,
      'requestId': options.requestId,
      'environment': config.environment,
      'release': config.release,
      'user': options.user,
      'tags': <String, Object?>{'octri.origin': 'standalone', ...?options.tags},
      'context': options.context,
      'breadcrumbs': options.breadcrumbs,
      'fingerprint': options.fingerprint,
      'traceId': options.trace?.traceId,
      'spanId': options.spanId,
    });
    unawaited(_post(config, '/ingest', payload, eventId));
  }

  static void captureError(
    Object error, {
    StackTrace? stackTrace,
    OctriErrorOptions options = const OctriErrorOptions(),
  }) {
    final config = _config;
    if (config == null) return;
    final trace = options.trace ?? traceFromHeader(null);
    final eventId = _randomHex(16);
    final payload = _compact(<String, Object?>{
      'eventId': eventId,
      'timestamp': DateTime.now().toUtc().toIso8601String(),
      'level': options.level,
      'operationId': options.operationId,
      'method': options.method,
      'path': options.path,
      'statusCode': options.statusCode,
      'environment': config.environment,
      'release': config.release,
      'traceId': trace.traceId,
      'spanId': _randomHex(8),
      'tags': const <String, Object?>{'octri.origin': 'server'},
      'error': <String, Object?>{
        'name': error.runtimeType.toString(),
        'message': error.toString(),
        'stack': stackTrace?.toString(),
        'frames': const <Object?>[],
      },
    });
    unawaited(_post(config, '/ingest', payload, eventId));
  }

  static void captureSpan(OctriSpan span) {
    final config = _config;
    if (config == null) return;
    if (span.traceId.isEmpty || span.spanId.isEmpty || span.name.isEmpty) return;
    final payload = _compact(<String, Object?>{
      'traceId': span.traceId,
      'spanId': span.spanId,
      'parentSpanId': span.parentSpanId,
      'environment': config.environment,
      'name': span.name,
      'service': span.service,
      'operationId': span.operationId,
      'startTime': span.startTime.toUtc().toIso8601String(),
      'endTime': span.endTime?.toUtc().toIso8601String(),
      'status': span.status,
    });
    unawaited(
      _post(config, '/traces', payload, '${span.traceId}:${span.spanId}'),
    );
  }

  static Future<void> _post(
    OctriConfig config,
    String path,
    Map<String, Object?> payload,
    String idempotencyKey,
  ) async {
    HttpClient? client;
    try {
      if (!_safeHeaderValue(idempotencyKey) ||
          (config.token?.isNotEmpty == true &&
              !_safeHeaderValue(config.token!))) {
        return;
      }
      client = HttpClient()..connectionTimeout = const Duration(seconds: 1);
      final request = await client.postUrl(Uri.parse(config.url + path));
      request.headers.contentType = ContentType.json;
      request.headers.set('idempotency-key', idempotencyKey);
      final token = config.token;
      if (token != null && token.isNotEmpty) {
        request.headers.set('authorization', 'Bearer $token');
      }
      request.add(utf8.encode(jsonEncode(payload)));
      final response = await request.close().timeout(const Duration(seconds: 5));
      await response.drain<void>().timeout(const Duration(seconds: 5));
    } catch (_) {
      // Monitoring must never affect the application.
    } finally {
      client?.close(force: true);
    }
  }

  static Map<String, Object?> _compact(Map<String, Object?> values) =>
      Map<String, Object?>.fromEntries(
        values.entries.where((entry) => entry.value != null),
      );

  static bool _allZeros(String value) =>
      value.codeUnits.every((character) => character == 0x30);

  static bool _safeHeaderValue(String value) =>
      value.isNotEmpty && !value.contains('\r') && !value.contains('\n');

  static String _randomHex(int bytes) => List<int>.generate(
        bytes,
        (_) => _random.nextInt(256),
      ).map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
}
