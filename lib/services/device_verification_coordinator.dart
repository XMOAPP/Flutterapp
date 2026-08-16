import 'dart:async';
import 'dart:collection';

import 'package:flutter/material.dart';
import 'package:matrix/encryption/utils/key_verification.dart';

import '../providers/matrix_provider.dart';
import '../screens/device_verification_screen.dart';
import 'matrix_device_verification_service.dart';

class DeviceVerificationCoordinator {
  DeviceVerificationCoordinator._();

  static final instance = DeviceVerificationCoordinator._();

  StreamSubscription<KeyVerification>? _subscription;
  final Set<String> _presentedTransactions = <String>{};
  final Queue<KeyVerification> _pending = Queue<KeyVerification>();
  GlobalKey<NavigatorState>? _navigatorKey;
  MatrixProvider? _matrixProvider;
  bool _presenting = false;

  Future<void> init({
    required GlobalKey<NavigatorState> navigatorKey,
    required MatrixProvider matrixProvider,
  }) async {
    await _subscription?.cancel();
    _navigatorKey = navigatorKey;
    _matrixProvider = matrixProvider;
    _pending.clear();
    final service = MatrixDeviceVerificationService(matrixProvider.service);
    _subscription = service.incomingRequests.listen((verification) {
      if (!matrixProvider.isLoggedIn ||
          verification.userId != matrixProvider.userId ||
          verification.deviceId == matrixProvider.service.client.deviceID) {
        return;
      }
      _pending.add(verification);
      unawaited(_drain());
    });
  }

  Future<void> _drain() async {
    if (_presenting) return;
    final navigatorKey = _navigatorKey;
    final matrixProvider = _matrixProvider;
    if (navigatorKey == null || matrixProvider == null) return;

    while (_pending.isNotEmpty) {
      final verification = _pending.removeFirst();
      await _present(navigatorKey, matrixProvider, verification);
    }
  }

  Future<void> _present(
    GlobalKey<NavigatorState> navigatorKey,
    MatrixProvider matrixProvider,
    KeyVerification verification,
  ) async {
    final id =
        verification.transactionId ??
        '${verification.userId}:${verification.deviceId}:${verification.lastActivity.millisecondsSinceEpoch}';
    if (!_presentedTransactions.add(id)) return;

    final navigator = navigatorKey.currentState;
    if (navigator == null) {
      _presentedTransactions.remove(id);
      return;
    }
    _presenting = true;
    try {
      await navigator.push<bool>(
        MaterialPageRoute(
          builder: (_) => DeviceVerificationScreen(
            verification: verification,
            matrixService: matrixProvider.service,
          ),
        ),
      );
    } finally {
      _presenting = false;
      _presentedTransactions.remove(id);
    }
  }
}
