# Changelog

## 1.0.1

- Dartdoc comments on the whole public API, and a library comment.
- A runnable example under `example/`, showing an HTTP server that
  continues an inbound trace, reports an error against it and times the
  request.

## 1.0.0

First public release.

- Error reporting with original source context for each in-app stack frame.
- Request and sub-span timing, drawn as a waterfall in the dashboard.
- W3C `traceparent` propagation, so a server error links to the client SDK
  error for the same request.
- Standalone events with idempotent, best-effort delivery.
