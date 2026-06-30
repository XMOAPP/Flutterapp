import 'dart:io';

import '../http_utils.dart';

void handleHealth(HttpRequest request) {
  sendJson(request, HttpStatus.ok, {
    'ok': true,
    'service': 'xmo-auth',
    'timestamp': DateTime.now().toUtc().toIso8601String(),
  });
}
