# octri_monitoring (Dart)

**Error and performance monitoring for Dart applications.** Report a thrown
object with its stack trace, emit your own application events, time spans into a
request waterfall, and continue a W3C distributed trace that started in whichever
client called you.

Octri turns an OpenAPI spec into a documentation site, client SDKs for ten
languages, an MCP server your AI assistant can call, and monitoring for the
API behind them. This package is the Dart monitoring runtime, and it works on
its own: a generated Octri API SDK is not required. See
[octri.dev/monitoring](https://octri.dev/monitoring).

Dart 3.2 or newer, on the Dart VM. No runtime dependencies.

## Install

```bash
dart pub add octri_monitoring
```

## Setup

Call `init` once at startup.

```dart
import 'dart:io';
import 'package:octri_monitoring/octri_monitoring.dart';

Octri.init(OctriConfig(
  url: 'https://monitoring.example.com',            // your monitoring base URL
  token: Platform.environment['OCTRI_TOKEN'],       // your project ingest token
  environment: '<your project id>',                 // the dashboard project id
  release: Platform.environment['GIT_SHA'],         // optional
));
```

Hosted users copy the project-scoped URL, token, and environment from the
Monitoring connection settings in the dashboard. Pass `token: null` only when you
point at an open self-hosted ingest endpoint.

Every call is asynchronous, best effort, and carries an idempotency key.
Transport failures are suppressed, so a monitoring outage cannot affect the
process it is watching.

## Application events

```dart
Octri.captureEvent(
  'checkout.completed',
  options: const OctriEventOptions(
    level: 'info',
    tags: {'region': 'eu-west', 'plan': 'growth'},
    context: {'orderId': 'ord_912'},
  ),
);
```

`OctriEventOptions` also carries `user`, `breadcrumbs`, `fingerprint`,
`operationId`, `method`, `path`, `statusCode`, `latencyMs`, `attempt`, and
`requestId`. Supplying `eventId` makes a retried delivery idempotent.

## Errors

```dart
try {
  await handle(request);
} catch (error, stackTrace) {
  Octri.captureError(
    error,
    stackTrace: stackTrace,
    options: const OctriErrorOptions(
      method: 'POST',
      path: '/orders',
      statusCode: 500,
    ),
  );
}
```

Omitting `stackTrace` still reports the error, with the current stack.

## Joining the caller's trace

Your generated client SDK sends `traceparent: 00-<traceId>-<spanId>-01` on every
request. Read it on the way in and pass the result as `trace`, and the dashboard
groups the client call and the server error under one `traceId`: the request that
failed, beside the frame that threw.

```dart
final trace = Octri.traceFromHeader(request.headers.value('traceparent'));

Octri.captureError(error, options: OctriErrorOptions(trace: trace));
```

`traceFromHeader(null)` starts a fresh trace, so the same code path works for
traffic that arrives without a header.

## Spans

A span is a completed unit of work. Report one per request to get the waterfall,
and one per sub-operation to see where the time went inside it.

```dart
final started = DateTime.now();
final rows = await db.query(sql);

Octri.captureSpan(OctriSpan(
  traceId: trace.traceId,
  spanId: spanId,
  parentSpanId: trace.parentSpanId,
  name: 'orders.list',
  operationId: 'listOrders',
  startTime: started,
  endTime: DateTime.now(),
));
```

Spans sharing a `traceId` nest by `parentSpanId` in the dashboard waterfall.

---

## The rest of Octri

| Product | What it does |
|---|---|
| [API Studio](https://octri.dev/api-studio) | Your OpenAPI spec becomes a hosted documentation site with a live request playground, editable page by page. |
| [SDK Studio](https://octri.dev/sdk-studio) | The same spec becomes client libraries for ten languages, versioned and released together. |
| [MCP](https://octri.dev/mcp) | Your endpoints and docs become tools an AI assistant can call, generated from the same spec. |
| [Monitoring](https://octri.dev/monitoring) | Errors, traces, uptime and releases for the API, joined to the SDK calls that reached it. |

### Monitoring runtimes

- [Node](https://github.com/octridev/octri-node)
- [Python](https://github.com/octridev/octri-python)
- [Go](https://github.com/octridev/octri-go)
- [Ruby](https://github.com/octridev/octri-ruby)
- [Rust](https://github.com/octridev/octri-rust)
- [PHP](https://github.com/octridev/octri-php)
- [Java](https://github.com/octridev/octri-java)
- [Kotlin](https://github.com/octridev/octri-kotlin)
- [Swift](https://github.com/octridev/octri-swift)
- [Dart](https://github.com/octridev/octri-dart)

### More

- [Documentation](https://docs.octri.dev/docs)
- [Pricing](https://octri.dev/pricing)
- [Changelog](https://docs.octri.dev/changelog)

MIT licensed.
