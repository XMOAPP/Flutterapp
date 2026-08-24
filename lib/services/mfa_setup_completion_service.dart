import 'dart:async';

import '../config/app_config.dart';
import '../security/callback_uri_validation.dart';

/// Handles the verified App Link sent after Authentik completes TOTP setup.
///
/// This callback only updates local UI. Authentik remains the source of truth
/// for whether a TOTP device is enrolled and required during sign-in.
class MfaSetupCompletionService {
  MfaSetupCompletionService._();

  static final MfaSetupCompletionService instance =
      MfaSetupCompletionService._();

  static const actionParameter = 'xmo_action';
  static const completionAction = 'mfa_setup_complete';

  final StreamController<void> _completions = StreamController<void>.broadcast(
    sync: true,
  );
  bool _completionPending = false;

  Stream<void> get completions => _completions.stream;

  static Uri get completionUri {
    final callback = Uri.parse(AppConfig.ssoCallbackUrl.trim());
    return callback.replace(
      queryParameters: const {actionParameter: completionAction},
    );
  }

  static bool isCompletionUri(Uri uri) {
    final callback = Uri.tryParse(AppConfig.ssoCallbackUrl.trim());
    if (callback == null ||
        uri.scheme.toLowerCase() != callback.scheme.toLowerCase() ||
        uri.host.toLowerCase() != callback.host.toLowerCase() ||
        uri.port != callback.port ||
        uri.path != callback.path ||
        uri.queryParameters.length != 1 ||
        !hasOnlySingleAllowedQueryParameters(uri, {actionParameter})) {
      return false;
    }
    return uri.queryParameters[actionParameter] == completionAction;
  }

  bool handleLink(String value) {
    final uri = Uri.tryParse(value);
    if (uri == null || !isCompletionUri(uri)) return false;

    _completionPending = true;
    _completions.add(null);
    return true;
  }

  bool consumePendingCompletion() {
    final pending = _completionPending;
    _completionPending = false;
    return pending;
  }
}
