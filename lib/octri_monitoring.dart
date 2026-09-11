/// Standalone error and performance monitoring for Dart applications.
///
/// Call [Octri.init] once at startup with an [OctriConfig], then report
/// failures with [Octri.captureError], send your own events with
/// [Octri.captureEvent], and time work with [Octri.captureSpan].
///
/// Every send runs off the calling path and is best effort. A transport
/// failure is swallowed, so monitoring cannot break the code around it.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

/// Connection settings for one Octri monitoring project.
///
/// Hosted users can copy the URL, token and environment from the Monitoring
/// connection settings in the dashboard.
class OctriConfig {
  /// Creates settings pointing at the monitoring backend on [url].
  ///
  /// Any trailing slashes on [url] are removed, so `https://example.com` and
  /// `https://example.com/` behave identically.
  OctriConfig({
    required String url,
    this.token,
    required this.environment,
    this.release,
  }) : url = url.replaceFirst(RegExp(r'/+$'), '');

  /// Base URL of the monitoring backend, stored without a trailing slash.
  final String url;

  /// Optional only for open self-hosted ingestion. Hosted Octri requires it.
  final String? token;

  /// Dashboard project id that received events and spans are filed under.
  final String environment;

  /// Release this process is running, such as a commit SHA or a version.
  final String? release;
}

/// Identifies one W3C distributed trace, and the span that called into it.
///
/// Build one from an inbound request header with [Octri.traceFromHeader] so a
/// server error joins the client error for the same request.
class OctriTraceContext {
  /// Creates a context for [traceId], optionally nested under [parentSpanId].
  const OctriTraceContext(this.traceId, [this.parentSpanId]);

  /// Hexadecimal id, 32 characters long, shared by every span in the trace.
  final String traceId;

  /// Hexadecimal id, 16 characters long, of the span that called this process.
  ///
  /// Null when this process started the trace.
  final String? parentSpanId;
}

/// Optional detail attached to a call to [Octri.captureEvent].
///
/// Every field may be omitted. Fields left null are dropped from the payload
/// rather than sent as nulls.
class OctriEventOptions {
  /// Creates a set of event options.
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

  /// When the event happened. Defaults to the moment of the call.
  final DateTime? timestamp;

  /// Severity, such as `info`, `warning` or `error`. Defaults to `info`.
  final String level;

  /// OpenAPI operation id the event belongs to.
  final String? operationId;

  /// HTTP method of the request the event describes.
  final String? method;

  /// Request path the event describes.
  final String? path;

  /// HTTP status code the request ended with.
  final int? statusCode;

  /// How long the described work took, in milliseconds.
  final num? latencyMs;

  /// Retry number, counting from 1 for the first attempt.
  final int? attempt;

  /// Your own correlation id for the request.
  final String? requestId;

  /// Who the event happened to, such as `{'id': customer.id}`.
  final Map<String, Object?>? user;

  /// Searchable keys and values, such as region or plan.
  ///
  /// Octri adds `octri.origin` itself; your own tags are merged over it.
  final Map<String, Object?>? tags;

  /// Free-form detail shown alongside the event in the dashboard.
  final Map<String, Object?>? context;

  /// Steps leading up to the event, oldest first.
  final List<Map<String, Object?>>? breadcrumbs;

  /// Overrides how the dashboard groups this event with similar ones.
  final String? fingerprint;

  /// Trace the event belongs to, usually from [Octri.traceFromHeader].
  final OctriTraceContext? trace;

  /// Span within that trace the event was raised in.
  final String? spanId;

  /// Idempotency key for the delivery.
  ///
  /// Pass the same value when retrying a send so the backend stores it once. A
  /// value that is empty or contains a carriage return or newline is replaced
  /// with a random id.
  final String? eventId;
}

/// Optional detail attached to a call to [Octri.captureError].
class OctriErrorOptions {
  /// Creates a set of error options.
  const OctriErrorOptions({
    this.level = 'error',
    this.operationId,
    this.method,
    this.path,
    this.statusCode,
    this.trace,
  });

  /// Severity, such as `error` or `fatal`. Defaults to `error`.
  final String level;

  /// OpenAPI operation id the failure happened under.
  final String? operationId;

  /// HTTP method of the request that failed.
  final String? method;

  /// Request path that failed.
  final String? path;

  /// HTTP status code the failed request ended with.
  final int? statusCode;

  /// Trace to file the error under, usually from [Octri.traceFromHeader].
  ///
  /// When omitted, the error starts a new trace of its own.
  final OctriTraceContext? trace;
}

/// One timed unit of work, drawn as a bar in the dashboard waterfall.
class OctriSpan {
  /// Creates a span covering one piece of work.
  ///
  /// [Octri.captureSpan] drops any span whose [traceId], [spanId] or [name] is
  /// empty.
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

  /// Id of the trace this span belongs to.
  final String traceId;

  /// Id of this span, unique within the trace.
  final String spanId;

  /// Id of the enclosing span, or null when this is the root of the trace.
  final String? parentSpanId;

  /// Readable name for the work, such as `orders.list`.
  final String name;

  /// Side of the call the span was recorded on. Defaults to `server`.
  final String service;

  /// OpenAPI operation id the span belongs to.
  final String? operationId;

  /// When the work started.
  final DateTime startTime;

  /// When the work finished, or null while it is still running.
  final DateTime? endTime;

  /// How the work ended, such as `ok` or `error`. Defaults to `ok`.
  final String status;
}

/// Standalone Octri monitoring for Dart VM applications.
///
/// Delivery is asynchronous and best-effort. Transport failures are suppressed
/// so telemetry cannot affect the host application.
/// Hook run on every payload just before it is sent. Return the payload to send
/// it, or `null` to drop the event. See [Octri.setBeforeSend].
typedef OctriBeforeSend = Map<String, Object?>? Function(
  Map<String, Object?> payload,
);

abstract final class Octri {
  static const int _maxIdempotencyKeyLength = 256;
  static OctriConfig? _config;
  static final Random _random = Random.secure();
  static final RegExp _traceparent = RegExp(
    r'^00-([0-9a-f]{32})-([0-9a-f]{16})-[0-9a-f]{2}$',
    caseSensitive: false,
  );

  /// Points every later call at the project described by [config].
  ///
  /// Call this once at startup. Until it runs, [captureEvent],
  /// [captureError] and [captureSpan] return without sending anything.
  /// Calling it again replaces the settings for subsequent calls.
  static void init(OctriConfig config) {
    _config = config;
  }

  // ── Scrubbing ──────────────────────────────────────────────────────────────

  /// Keys whose value never leaves the process. Compared against the key with
  /// case and separators removed, so `api_key`, `apiKey` and `API-KEY` all match
  /// `apikey`, and the test is a substring one, so `stripeSecretKey` matches too.
  static const List<String> _scrubKeys = [
    'password',
    'passwd',
    'passphrase',
    'secret',
    'token',
    'apikey',
    'authorization',
    'credential',
    'cookie',
    'session',
    'privatekey',
    'accesskey',
    'cardnumber',
    'creditcard',
    'cvv',
    'ssn',
  ];

  static const String _redacted = '[redacted]';
  static const String _truncated = '[truncated]';
  static const String _circular = '[circular]';

  /// Deep enough for real context maps, shallow enough to stay cheap.
  static const int _maxScrubDepth = 8;

  static final RegExp _bearer =
      RegExp(r'\bbearer\s+[\w.~+/-]+=*', caseSensitive: false);
  static final RegExp _jwt = RegExp(r'\beyJ[\w-]+\.[\w-]+\.[\w-]+');
  static final RegExp _digitRun = RegExp(r'\b(?:\d[ -]?){12,18}\d\b');
  static final RegExp _email = RegExp(r'[\w.%+-]+@[\w-]+(?:\.[\w-]+)+');
  static final RegExp _nonDigit = RegExp(r'\D');
  static final RegExp _nonAlphanumeric = RegExp('[^a-z0-9]');

  static final List<String> _extraScrubKeys = [];
  static OctriBeforeSend? _beforeSend;

  /// Redacts more key names, on top of the built-in list.
  ///
  /// Matching ignores case and separators and is a substring test, so
  /// `account` also covers `accountNumber`:
  ///
  /// ```dart
  /// Octri.addScrubFields(['accountNumber', 'otp']);
  /// ```
  static void addScrubFields(Iterable<String> fields) {
    for (final field in fields) {
      final key = _normalizeKey(field);
      if (key.isNotEmpty && !_extraScrubKeys.contains(key)) {
        _extraScrubKeys.add(key);
      }
    }
  }

  /// Runs [hook] on every payload just before it is sent.
  ///
  /// Return the payload (editing it is fine) to send it, or `null` to drop the
  /// event:
  ///
  /// ```dart
  /// Octri.setBeforeSend((payload) => payload['path'] == '/health' ? null : payload);
  /// ```
  ///
  /// Redaction still runs afterwards, so a hook cannot leak a credential by
  /// accident. Pass `null` to remove the hook.
  static void setBeforeSend(OctriBeforeSend? hook) {
    _beforeSend = hook;
  }

  static String _normalizeKey(String key) =>
      key.toLowerCase().replaceAll(_nonAlphanumeric, '');

  static bool _isSecretKey(String key) {
    final normalized = _normalizeKey(key);
    if (normalized.isEmpty) return false;
    return _scrubKeys.any((candidate) => normalized.contains(candidate)) ||
        _extraScrubKeys.any((candidate) => normalized.contains(candidate));
  }

  /// Tells a card number from the order ids and timestamps that look like one.
  static bool _passesLuhn(String digits) {
    var sum = 0;
    var doubling = false;
    for (var index = digits.length - 1; index >= 0; index--) {
      var digit = digits.codeUnitAt(index) - 0x30;
      if (doubling) {
        digit *= 2;
        if (digit > 9) digit -= 9;
      }
      sum += digit;
      doubling = !doubling;
    }
    return sum % 10 == 0;
  }

  /// Removes credentials and personal data that leaked into free text.
  static String _scrubText(String value) {
    if (value.isEmpty) return value;
    var scrubbed = value.replaceAll(_bearer, _redacted);
    scrubbed = scrubbed.replaceAll(_jwt, _redacted);
    scrubbed = scrubbed.replaceAllMapped(_digitRun, (match) {
      final run = match[0]!;
      return _passesLuhn(run.replaceAll(_nonDigit, '')) ? _redacted : run;
    });
    return scrubbed.replaceAll(_email, _redacted);
  }

  /// Redacts credential-shaped keys anywhere in the payload, and strips secrets
  /// out of the free text around them. `user` is the field you deliberately fill
  /// with an identity, so its strings are left alone; its keys are still checked.
  static Object? _scrubValue(
    Object? value,
    int depth,
    bool text,
    Set<Object> seen,
  ) {
    if (value is String) return text ? _scrubText(value) : value;
    if (value is! Map && value is! Iterable) return value;
    if (depth >= _maxScrubDepth) return _truncated;
    final container = value as Object;
    // Walking a copy means a cycle would recurse forever, and a context map
    // holding a reference back to itself is worth surviving.
    if (!seen.add(container)) return _circular;
    try {
      if (container is Iterable) {
        return container
            .map((item) => _scrubValue(item, depth + 1, text, seen))
            .toList();
      }
      final out = <String, Object?>{};
      (container as Map).forEach((key, nested) {
        final name = key.toString();
        out[name] = _isSecretKey(name)
            ? _redacted
            : _scrubValue(nested, depth + 1, text && name != 'user', seen);
      });
      return out;
    } finally {
      seen.remove(container);
    }
  }

  /// The last thing every payload passes through. Both the hook and the
  /// redaction live here rather than in the capture methods, so nothing can be
  /// reported around them.
  static Map<String, Object?>? _scrubPayload(Map<String, Object?> payload) {
    final hook = _beforeSend;
    final hooked = hook == null ? payload : hook(payload);
    if (hooked == null) return null;
    return _scrubValue(hooked, 0, true, Set<Object>.identity())
        as Map<String, Object?>;
  }

  /// Reads a W3C `traceparent` header into a trace context.
  ///
  /// Returns the trace and parent span carried by [traceparent] when it is a
  /// well-formed version `00` header. Returns a context holding a fresh random
  /// trace id and no parent when the header is null, malformed, or carries an
  /// all-zero trace or parent id, so the caller always gets a usable trace.
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
  ///
  /// Records [message] against the configured project, with any detail given
  /// in [options]. Returns immediately; the send happens in the background.
  /// Does nothing when [init] has not run.
  static void captureEvent(
    String message, {
    OctriEventOptions options = const OctriEventOptions(),
  }) {
    final config = _config;
    if (config == null) return;
    final requestedEventId = options.eventId;
    final eventId =
        requestedEventId != null && _safeIdempotencyKey(requestedEventId)
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

  /// Reports a thrown [error] and its [stackTrace] to the dashboard.
  ///
  /// Files the error under the trace in [options], or under a new trace of its
  /// own when none is given. Pass the trace from
  /// [traceFromHeader] to join the error to the client error for the same
  /// request. Returns immediately; the send happens in the background. Does
  /// nothing when [init] has not run.
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

  /// Records [span] as one bar in the dashboard request waterfall.
  ///
  /// Ignores a span whose trace id, span id or name is empty. Returns
  /// immediately; the send happens in the background. Does nothing when [init]
  /// has not run.
  static void captureSpan(OctriSpan span) {
    final config = _config;
    if (config == null) return;
    if (span.traceId.isEmpty || span.spanId.isEmpty || span.name.isEmpty) {
      return;
    }
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
      if (!_safeIdempotencyKey(idempotencyKey) ||
          (config.token?.isNotEmpty == true &&
              !_safeHeaderValue(config.token!))) {
        return;
      }
      final scrubbed = _scrubPayload(payload);
      if (scrubbed == null) return;
      client = HttpClient()..connectionTimeout = const Duration(seconds: 1);
      final request = await client.postUrl(Uri.parse(config.url + path));
      request.headers.contentType = ContentType.json;
      request.headers.set('idempotency-key', idempotencyKey);
      final token = config.token;
      if (token != null && token.isNotEmpty) {
        request.headers.set('authorization', 'Bearer $token');
      }
      request.add(utf8.encode(jsonEncode(scrubbed)));
      final response =
          await request.close().timeout(const Duration(seconds: 5));
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

  /// A caller-supplied event id becomes the `idempotency-key` header, so it is
  /// bounded as well as newline-free.
  static bool _safeIdempotencyKey(String value) =>
      _safeHeaderValue(value) &&
      utf8.encode(value).length <= _maxIdempotencyKeyLength;

  static String _randomHex(int bytes) => List<int>.generate(
        bytes,
        (_) => _random.nextInt(256),
      ).map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
}
