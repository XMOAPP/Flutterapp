import 'package:flutter/services.dart';

class SensitiveScreenService {
  const SensitiveScreenService();

  static const _channel = MethodChannel('com.xmo.xmo/sensitive_screen');

  Future<void> setProtected(bool protected) async {
    try {
      await _channel.invokeMethod<void>('setProtected', protected);
    } on MissingPluginException {
      // Unsupported platforms still receive the in-app obscuring behavior.
    }
  }
}
