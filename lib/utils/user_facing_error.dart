/// Converts technical failures into text that is safe to display to users.
///
/// Exception details belong in diagnostics, never in snackbars, dialogs, or
/// error labels. In particular, network exceptions can contain internal URLs,
/// hostnames, IP addresses, file paths, and request payload details.
String userFacingError(Object? error, {required String fallback}) {
  final raw = error?.toString().toLowerCase() ?? '';
  if (raw.contains('m_limit_exceeded') ||
      raw.contains('too many requests') ||
      raw.contains('rate limit')) {
    return 'Too many requests. Please wait and try again.';
  }
  if (raw.contains('m_user_in_use') || raw.contains('username already')) {
    return 'Username already taken.';
  }
  if ((raw.contains('verification code') || raw.contains('otp')) &&
      (raw.contains('invalid') ||
          raw.contains('expired') ||
          raw.contains('incorrect'))) {
    return 'The verification code is invalid or expired.';
  }
  if (raw.contains('email verification expired')) {
    return 'Email verification expired. Please request a new code.';
  }
  if (raw.contains('m_forbidden') ||
      raw.contains('invalid username') ||
      raw.contains('invalid password')) {
    return 'The credentials are incorrect or this action is not allowed.';
  }
  if (raw.contains('timed out') || raw.contains('timeoutexception')) {
    return 'The request timed out. Please try again.';
  }
  if (raw.contains('socketexception') ||
      raw.contains('handshakeexception') ||
      raw.contains('clientexception') ||
      raw.contains('failed host lookup') ||
      raw.contains('connection refused') ||
      raw.contains('connection reset') ||
      raw.contains('network is unreachable') ||
      raw.contains('no address associated with hostname')) {
    return 'Connection failed. Check your internet connection and try again.';
  }
  if (raw.contains('permission') || raw.contains('not allowed')) {
    return 'Permission denied. Check access and try again.';
  }
  if (raw.contains('not found') || raw.contains('m_not_found')) {
    return 'The requested account or item could not be found.';
  }
  if (raw.contains('group has reached') || raw.contains('50-member limit')) {
    return 'This group has reached its 50-member limit.';
  }
  if (raw.contains('channel has reached') || raw.contains('100-member limit')) {
    return 'This channel has reached its 100-member limit.';
  }
  if (raw.contains('too large') || raw.contains('m_too_large')) {
    return 'This file is larger than the allowed upload size.';
  }

  final safePlainMessage = _safePlainMessage(error);
  if (safePlainMessage != null) return safePlainMessage;

  return fallback;
}

/// Sanitizes a legacy UI message that already contains exception text.
///
/// New code should prefer [userFacingError] and pass the exception separately.
String safeUserFacingText(String message, {String? fallback}) {
  final separator = message.indexOf(': ');
  final action = separator > 0 ? message.substring(0, separator).trim() : '';
  final details = separator > 0 ? message.substring(separator + 2) : message;
  final safeFallback =
      fallback ??
      (action.isEmpty ? 'Something went wrong. Please try again.' : '$action.');
  return userFacingError(details, fallback: safeFallback);
}

String? _safePlainMessage(Object? error) {
  if (error is! String) return null;
  final message = error.trim();
  if (message.isEmpty || message.length > 180 || message.contains('\n')) {
    return null;
  }

  final lower = message.toLowerCase();
  const technicalMarkers = [
    'exception',
    'stack trace',
    'http://',
    'https://',
    'uri=',
    'hostname',
    'socket',
    'database',
    'select ',
    'insert ',
    'update ',
    'delete from ',
    'package:',
    'dart:',
    'file://',
    'os error',
  ];
  if (technicalMarkers.any(lower.contains)) return null;

  final domainPattern = RegExp(
    r'\b[a-z0-9-]+(?:\.[a-z0-9-]+)+(?:[/:?][^\s]*)?',
    caseSensitive: false,
  );
  final ipv4Pattern = RegExp(r'\b(?:\d{1,3}\.){3}\d{1,3}\b');
  if (domainPattern.hasMatch(message) || ipv4Pattern.hasMatch(message)) {
    return null;
  }

  return message;
}
