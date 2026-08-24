import 'dart:async';

import 'package:flutter/material.dart';

import '../config/app_config.dart';
import '../providers/matrix_provider.dart';

class AccountDeletionCompletionService with WidgetsBindingObserver {
  AccountDeletionCompletionService._();

  static final AccountDeletionCompletionService instance =
      AccountDeletionCompletionService._();

  static const actionParameter = 'xmo_action';
  static const completionAction = 'account_deleted';
  static final Uri _fallbackCompletionUri = Uri.parse('xmo://account/deleted');

  GlobalKey<NavigatorState>? _navigatorKey;
  MatrixProvider? _matrixProvider;
  bool _observingLifecycle = false;
  bool _checkingSession = false;

  void init({
    required GlobalKey<NavigatorState> navigatorKey,
    required MatrixProvider matrixProvider,
  }) {
    _navigatorKey = navigatorKey;
    _matrixProvider = matrixProvider;
    if (!_observingLifecycle) {
      WidgetsBinding.instance.addObserver(this);
      _observingLifecycle = true;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    unawaited(_checkForCompletedRemoteDeletion());
    // Account deletion is processed asynchronously on the backend. A second
    // check catches the normal case where the browser returns before the job
    // has revoked the Matrix access token.
    Future<void>.delayed(const Duration(seconds: 3), () async {
      await _checkForCompletedRemoteDeletion();
    });
  }

  static Uri completionUri({required String userId}) {
    final completion = Uri.parse(AppConfig.accountDeletionCompletionUrl.trim());
    return completion.replace(
      queryParameters: {actionParameter: completionAction, 'user_id': userId},
    );
  }

  static bool isCompletionUri(Uri uri) {
    final completion = Uri.tryParse(
      AppConfig.accountDeletionCompletionUrl.trim(),
    );
    final isVerifiedHttpsCallback =
        completion != null &&
        uri.userInfo.isEmpty &&
        uri.fragment.isEmpty &&
        uri.scheme.toLowerCase() == completion.scheme.toLowerCase() &&
        uri.host.toLowerCase() == completion.host.toLowerCase() &&
        uri.port == completion.port &&
        uri.path == completion.path;
    final isFallbackCallback =
        uri.userInfo.isEmpty &&
        uri.fragment.isEmpty &&
        uri.scheme.toLowerCase() == _fallbackCompletionUri.scheme &&
        uri.host.toLowerCase() == _fallbackCompletionUri.host &&
        uri.path == _fallbackCompletionUri.path;
    if (!isVerifiedHttpsCallback && !isFallbackCallback) return false;

    return uri.queryParameters.length == 2 &&
        uri.queryParameters[actionParameter] == completionAction &&
        (uri.queryParameters['user_id']?.trim().isNotEmpty ?? false);
  }

  Future<bool> handleLink(String value) async {
    final uri = Uri.tryParse(value);
    if (uri == null || !isCompletionUri(uri)) return false;

    final cleared =
        await _matrixProvider?.clearLocalSessionAfterRemoteDeletion(
          uri.queryParameters['user_id'],
        ) ??
        false;
    _showStatus(
      cleared
          ? 'Account deleted. Local session cleared.'
          : 'Account deleted. Sign out of any open XMO sessions.',
    );
    return true;
  }

  /// Checks the currently restored Matrix session after app startup. This is
  /// public so main can run it after credential restoration is complete.
  Future<void> checkCurrentSession() => _checkForCompletedRemoteDeletion();

  Future<void> _checkForCompletedRemoteDeletion() async {
    if (_checkingSession) return;
    _checkingSession = true;
    try {
      final cleared =
          await _matrixProvider?.clearLocalSessionIfServerInvalidated() ??
          false;
      if (cleared) {
        _showStatus('Account deleted. Local session cleared.');
      }
    } finally {
      _checkingSession = false;
    }
  }

  void _showStatus(String message) {
    final context = _navigatorKey?.currentContext;
    if (context == null) return;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: const Color(0xFF8FE63F),
        duration: const Duration(seconds: 3),
      ),
    );
  }
}
