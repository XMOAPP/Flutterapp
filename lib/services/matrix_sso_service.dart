import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:url_launcher/url_launcher.dart';

import '../config/app_config.dart';

class MatrixSsoException implements Exception {
  const MatrixSsoException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Coordinates a Synapse SSO browser flow and verifies the app callback before
/// exposing its one-time Matrix login token to the sign-in screen.
class MatrixSsoService {
  MatrixSsoService._();

  static final MatrixSsoService instance = MatrixSsoService._();
  static final Uri _legacyCallback = Uri.parse('xmo://auth/callback');

  Completer<String>? _pendingToken;
  String? _state;

  bool get isAwaitingCallback => _pendingToken != null;

  Future<String> startSignIn() async {
    if (!AppConfig.isSsoLoginConfigured) {
      throw const MatrixSsoException('Secure sign-in is not configured yet.');
    }
    if (_pendingToken != null) {
      throw const MatrixSsoException('Secure sign-in is already in progress.');
    }

    final homeserver = Uri.tryParse(AppConfig.homeserverUrl);
    if (homeserver == null ||
        (homeserver.scheme != 'https' && homeserver.scheme != 'http') ||
        homeserver.host.isEmpty) {
      throw const MatrixSsoException('The XMO homeserver URL is invalid.');
    }

    final state = _newState();
    final configuredCallback = Uri.parse(AppConfig.ssoCallbackUrl.trim());
    final callback = configuredCallback.replace(
      queryParameters: {'state': state},
    );
    final redirectPath = [
      ...homeserver.pathSegments.where((segment) => segment.isNotEmpty),
      '_matrix',
      'client',
      'v3',
      'login',
      'sso',
      'redirect',
      AppConfig.ssoIdpId,
    ];
    final authorizeUri = homeserver.replace(
      pathSegments: redirectPath,
      queryParameters: {'redirectUrl': callback.toString()},
    );

    final pending = Completer<String>();
    _pendingToken = pending;
    _state = state;
    bool launched;
    try {
      launched = await launchUrl(
        authorizeUri,
        mode: LaunchMode.externalApplication,
      );
    } catch (_) {
      _clearPending();
      throw const MatrixSsoException('Could not open secure sign-in.');
    }
    if (!launched) {
      _clearPending();
      throw const MatrixSsoException('Could not open secure sign-in.');
    }
    return pending.future.timeout(
      const Duration(minutes: 5),
      onTimeout: () {
        if (identical(_pendingToken, pending)) _clearPending();
        throw const MatrixSsoException(
          'Secure sign-in timed out. Please try again.',
        );
      },
    );
  }

  /// Called by the existing app-link dispatcher. Returns true for SSO links
  /// even if they are stale, preventing the token from reaching other handlers.
  bool handleLink(String value) {
    final uri = Uri.tryParse(value);
    if (uri == null || !isSupportedCallbackUri(uri)) {
      return false;
    }

    final pending = _pendingToken;
    final expectedState = _state;
    if (pending == null || expectedState == null) return true;

    final returnedState = uri.queryParameters['state'];
    final token =
        uri.queryParameters['loginToken'] ?? uri.queryParameters['login_token'];
    final error = uri.queryParameters['error'];
    if (!_constantTimeEquals(returnedState, expectedState)) {
      pending.completeError(
        const MatrixSsoException(
          'Secure sign-in verification failed. Please try again.',
        ),
      );
    } else if (error != null && error.isNotEmpty) {
      pending.completeError(
        const MatrixSsoException('Secure sign-in was cancelled.'),
      );
    } else if (token == null || token.isEmpty) {
      pending.completeError(
        const MatrixSsoException(
          'Secure sign-in did not return a login token.',
        ),
      );
    } else {
      pending.complete(token);
    }
    _clearPending();
    return true;
  }

  static bool isSupportedCallbackUri(Uri uri) {
    final configured = Uri.tryParse(AppConfig.ssoCallbackUrl.trim());
    if (configured != null &&
        uri.scheme.toLowerCase() == configured.scheme.toLowerCase() &&
        uri.host.toLowerCase() == configured.host.toLowerCase() &&
        uri.port == configured.port &&
        uri.path == configured.path) {
      return true;
    }
    return AppConfig.enableLegacySsoCallback &&
        uri.scheme.toLowerCase() == _legacyCallback.scheme &&
        uri.host.toLowerCase() == _legacyCallback.host &&
        uri.path == _legacyCallback.path;
  }

  String _newState() {
    final random = Random.secure();
    final bytes = List<int>.generate(32, (_) => random.nextInt(256));
    return base64UrlEncode(bytes).replaceAll('=', '');
  }

  bool _constantTimeEquals(String? first, String second) {
    if (first == null || first.length != second.length) return false;
    var difference = 0;
    for (var index = 0; index < first.length; index++) {
      difference |= first.codeUnitAt(index) ^ second.codeUnitAt(index);
    }
    return difference == 0;
  }

  void _clearPending() {
    _pendingToken = null;
    _state = null;
  }
}
