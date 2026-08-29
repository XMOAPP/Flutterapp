import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config/app_config.dart';
import '../security/callback_uri_validation.dart';

class MatrixSsoException implements Exception {
  const MatrixSsoException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Coordinates a Synapse SSO browser flow and verifies the app callback before
/// exposing its one-time Matrix login token to the sign-in screen.
class MatrixSsoService {
  MatrixSsoService._({FlutterSecureStorage? secureStorage})
    : _secureStorage = secureStorage ?? const FlutterSecureStorage();

  static final MatrixSsoService instance = MatrixSsoService._();
  static final Uri _legacyCallback = Uri.parse('xmo://auth/callback');
  static const _pendingStateStorageKey = 'xmo_matrix_sso_pending_state_v1';
  static const _signInLifetime = Duration(minutes: 5);

  final FlutterSecureStorage _secureStorage;

  Completer<String>? _pendingToken;
  String? _state;
  String? _recoveredToken;
  Future<bool> Function(String token)? _recoveredTokenHandler;

  bool get isAwaitingCallback => _pendingToken != null;

  void cancelPendingSignIn({
    String message = 'Secure sign-in was cancelled. Please try again.',
  }) {
    final pending = _pendingToken;
    _clearPendingMemory();
    unawaited(_clearPersistedState());
    if (pending == null) return;
    if (!pending.isCompleted) {
      pending.completeError(MatrixSsoException(message));
    }
  }

  void setRecoveredTokenHandler(Future<bool> Function(String token) handler) {
    _recoveredTokenHandler = handler;
    unawaited(_drainRecoveredToken());
  }

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
    try {
      await _persistState(state);
    } catch (_) {
      throw const MatrixSsoException(
        'Could not prepare secure sign-in. Please try again.',
      );
    }
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
      _clearPendingMemory();
      await _clearPersistedState();
      throw const MatrixSsoException('Could not open secure sign-in.');
    }
    if (!launched) {
      _clearPendingMemory();
      await _clearPersistedState();
      throw const MatrixSsoException('Could not open secure sign-in.');
    }
    return pending.future.timeout(
      _signInLifetime,
      onTimeout: () {
        if (identical(_pendingToken, pending)) {
          _clearPendingMemory();
          unawaited(_clearPersistedState());
        }
        throw const MatrixSsoException(
          'Secure sign-in timed out. Please try again.',
        );
      },
    );
  }

  /// Called by the existing app-link dispatcher. Returns true for SSO links
  /// even if they are stale, preventing the token from reaching other handlers.
  Future<bool> handleLink(String value) async {
    final uri = Uri.tryParse(value);
    if (uri == null || !isSupportedCallbackUri(uri)) {
      return false;
    }

    final pending = _pendingToken;
    final expectedState = _state ?? await _readPersistedState();
    if (expectedState == null) {
      await _clearPersistedState();
      return true;
    }

    final returnedState = uri.queryParameters['state'];
    final token =
        uri.queryParameters['loginToken'] ?? uri.queryParameters['login_token'];
    final error = uri.queryParameters['error'];
    if (!_constantTimeEquals(returnedState, expectedState)) {
      if (pending != null && !pending.isCompleted) {
        pending.completeError(
          const MatrixSsoException(
            'Secure sign-in verification failed. Please try again.',
          ),
        );
      }
    } else if (error != null && error.isNotEmpty) {
      if (pending != null && !pending.isCompleted) {
        pending.completeError(
          const MatrixSsoException('Secure sign-in was cancelled.'),
        );
      }
    } else if (token == null || token.isEmpty) {
      if (pending != null && !pending.isCompleted) {
        pending.completeError(
          const MatrixSsoException(
            'Secure sign-in did not return a login token.',
          ),
        );
      }
    } else if (pending != null && !pending.isCompleted) {
      pending.complete(token);
    } else {
      _recoveredToken = token;
      unawaited(_drainRecoveredToken());
    }
    _clearPendingMemory();
    await _clearPersistedState();
    return true;
  }

  static bool isSupportedCallbackUri(Uri uri) {
    final configured = Uri.tryParse(AppConfig.ssoCallbackUrl.trim());
    final hasAllowedQuery = hasOnlySingleAllowedQueryParameters(uri, {
      'state',
      'loginToken',
      'login_token',
      'error',
    });
    final hasAmbiguousTokenAlias =
        uri.queryParameters.containsKey('loginToken') &&
        uri.queryParameters.containsKey('login_token');
    if (configured != null &&
        hasAllowedQuery &&
        !hasAmbiguousTokenAlias &&
        uri.scheme.toLowerCase() == configured.scheme.toLowerCase() &&
        uri.host.toLowerCase() == configured.host.toLowerCase() &&
        uri.port == configured.port &&
        uri.path == configured.path) {
      return true;
    }
    return AppConfig.enableLegacySsoCallback &&
        hasAllowedQuery &&
        !hasAmbiguousTokenAlias &&
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

  Future<void> _persistState(String state) async {
    final expiresAt = DateTime.now()
        .add(_signInLifetime)
        .millisecondsSinceEpoch;
    await _secureStorage.write(
      key: _pendingStateStorageKey,
      value: jsonEncode({'state': state, 'expiresAt': expiresAt}),
    );
  }

  Future<String?> _readPersistedState() async {
    try {
      final encoded = await _secureStorage.read(key: _pendingStateStorageKey);
      if (encoded == null || encoded.isEmpty) return null;
      final decoded = jsonDecode(encoded);
      if (decoded is! Map<String, dynamic>) return null;
      final state = decoded['state'];
      final expiresAt = decoded['expiresAt'];
      if (state is! String ||
          state.isEmpty ||
          expiresAt is! int ||
          DateTime.now().millisecondsSinceEpoch >= expiresAt) {
        return null;
      }
      return state;
    } catch (error) {
      debugPrint('[MatrixSsoService] Could not restore pending sign-in state.');
      return null;
    }
  }

  Future<void> _clearPersistedState() async {
    try {
      await _secureStorage.delete(key: _pendingStateStorageKey);
    } catch (_) {
      debugPrint('[MatrixSsoService] Could not clear pending sign-in state.');
    }
  }

  Future<void> _drainRecoveredToken() async {
    final token = _recoveredToken;
    final handler = _recoveredTokenHandler;
    if (token == null || handler == null) return;
    _recoveredToken = null;
    try {
      final handled = await handler(token);
      if (!handled) {
        debugPrint('[MatrixSsoService] Recovered secure sign-in was rejected.');
      }
    } catch (error, stack) {
      debugPrint('[MatrixSsoService] Recovered secure sign-in failed.');
      debugPrintStack(stackTrace: stack);
    }
  }

  void _clearPendingMemory() {
    _pendingToken = null;
    _state = null;
  }
}
