# Octri Monitoring for Dart

Standalone events, error capture, W3C trace propagation, and span ingestion for
Dart VM applications.

```dart
import 'package:octri_monitoring/octri_monitoring.dart';

Octri.init(OctriConfig(
  url: 'https://monitoring.example.com',
  token: Platform.environment['OCTRI_TOKEN'],
  environment: '<your project id>',
  release: Platform.environment['GIT_SHA'],
));

Octri.captureEvent('checkout.completed', options: OctriEventOptions(
  tags: {'region': 'eu-west', 'plan': 'growth'},
  context: {'orderId': order.id, 'total': order.total},
));
```

The project-scoped URL, token, and environment are shown in Octri's Monitoring
connection settings. Set `token: null` only for an open self-hosted endpoint.
Delivery is asynchronous, best-effort, and idempotency-keyed.
