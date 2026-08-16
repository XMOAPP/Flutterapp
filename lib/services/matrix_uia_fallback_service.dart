import 'package:matrix/matrix.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config/app_config.dart';

class MatrixUiaFallbackException implements Exception {
  const MatrixUiaFallbackException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Opens Matrix's browser fallback for an interactive-authentication stage.
///
/// After the user completes the browser flow, the original request must be
/// retried with the same UIA session. This service deliberately does not treat
/// the fallback page as a Matrix login callback: it authorizes one sensitive
/// operation only.
class MatrixUiaFallbackService {
  const MatrixUiaFallbackService();

  static const supportedTypes = <String>{AuthenticationTypes.sso};

  bool supports(Iterable<String> stages) => stages.any(supportedTypes.contains);

  Future<void> open({
    required String authenticationType,
    required String? session,
  }) async {
    if (!supportedTypes.contains(authenticationType)) {
      throw const MatrixUiaFallbackException(
        'This account confirmation method is not supported.',
      );
    }
    if (session == null || session.isEmpty) {
      throw const MatrixUiaFallbackException(
        'The account server did not return a confirmation session.',
      );
    }

    final homeserver = Uri.tryParse(AppConfig.homeserverUrl.trim());
    if (homeserver == null ||
        !homeserver.hasAuthority ||
        (homeserver.scheme != 'https' && homeserver.scheme != 'http')) {
      throw const MatrixUiaFallbackException(
        'The XMO homeserver URL is invalid.',
      );
    }

    final pathSegments = <String>[
      ...homeserver.pathSegments.where((segment) => segment.isNotEmpty),
      '_matrix',
      'client',
      'v3',
      'auth',
      authenticationType,
      'fallback',
      'web',
    ];
    final uri = homeserver.replace(
      pathSegments: pathSegments,
      queryParameters: {'session': session},
    );
    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!launched) {
      throw const MatrixUiaFallbackException(
        'Could not open secure account confirmation.',
      );
    }
  }

  AuthenticationData completedSession(String? session) =>
      AuthenticationData(session: session);
}
