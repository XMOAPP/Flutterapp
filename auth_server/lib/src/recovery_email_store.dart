import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';

/// Stores only recovery email addresses that were bound through a trusted
/// enrollment flow. Legacy username-to-email files are intentionally never
/// imported: their entries could have been created by the former public
/// linking endpoint.
class RecoveryEmailStore {
  RecoveryEmailStore({
    required this.ttl,
    File? storageFile,
    Random? random,
    DateTime Function()? now,
  }) : _storageFile = storageFile,
       _random = random ?? Random.secure(),
       _now = now ?? (() => DateTime.now().toUtc()) {
    _load();
    prune();
  }

  final Duration ttl;
  final File? _storageFile;
  final Random _random;
  final DateTime Function() _now;
  final Map<String, _VerifiedRecoveryEmail> _verified = {};
  final Map<String, RecoveryEmailLocalEnrollment> _pendingLocalEnrollments = {};
  final Map<String, _PendingRecoveryEmailChange> _pendingChanges = {};

  /// Creates a one-use ticket after an email OTP has been verified during a
  /// new local Matrix registration. The caller must still prove ownership of
  /// the newly-created Matrix account before [claimLocalEnrollment] succeeds.
  String issueLocalEnrollment({
    required String username,
    required String email,
  }) {
    prune();
    final ticket = _newSecret();
    _pendingLocalEnrollments[_digest(ticket)] = RecoveryEmailLocalEnrollment(
      username: username,
      email: email,
      expiresAt: _now().add(ttl),
    );
    _persist();
    return ticket;
  }

  RecoveryEmailLocalEnrollment? claimLocalEnrollment({
    required String ticket,
    required String username,
  }) {
    prune();
    final digest = _digest(ticket);
    final record = _pendingLocalEnrollments[digest];
    if (record == null || record.username != username) return null;
    _pendingLocalEnrollments.remove(digest);
    _persist();
    return record;
  }

  void restoreLocalEnrollment({
    required String ticket,
    required RecoveryEmailLocalEnrollment record,
  }) {
    if (_now().isBefore(record.expiresAt)) {
      _pendingLocalEnrollments[_digest(ticket)] = record;
      _persist();
    }
  }

  void setVerified({required String username, required String email}) {
    _verified[username] = _VerifiedRecoveryEmail(
      email: email,
      verifiedAt: _now(),
    );
    _persist();
  }

  String? verifiedEmailFor(String username) {
    prune();
    return _verified[username]?.email;
  }

  bool hasVerifiedEmail(String username, String email) =>
      verifiedEmailFor(username) == email;

  String? removeVerified(String username) {
    final removed = _verified.remove(username)?.email;
    if (removed != null) _persist();
    return removed;
  }

  RecoveryEmailChangeIssue issueChange({
    required String username,
    required String currentEmail,
    required String newEmail,
  }) {
    prune();
    final transactionId = _newSecret();
    final currentEmailCode = _newCode();
    final newEmailCode = _newCode();
    _pendingChanges[_digest(transactionId)] = _PendingRecoveryEmailChange(
      username: username,
      currentEmail: currentEmail,
      newEmail: newEmail,
      currentEmailCodeDigest: _digest(currentEmailCode),
      newEmailCodeDigest: _digest(newEmailCode),
      expiresAt: _now().add(ttl),
    );
    _persist();
    return RecoveryEmailChangeIssue(
      transactionId: transactionId,
      currentEmailCode: currentEmailCode,
      newEmailCode: newEmailCode,
    );
  }

  String? claimChange({
    required String transactionId,
    required String username,
    required String currentEmailCode,
    required String newEmailCode,
  }) {
    prune();
    final digest = _digest(transactionId);
    final record = _pendingChanges[digest];
    if (record == null || record.username != username) return null;
    if (record.currentEmailCodeDigest != _digest(currentEmailCode) ||
        record.newEmailCodeDigest != _digest(newEmailCode)) {
      record.attempts += 1;
      if (record.attempts >= 5) _pendingChanges.remove(digest);
      _persist();
      return null;
    }
    _pendingChanges.remove(digest);
    _persist();
    return record.newEmail;
  }

  void prune() {
    final current = _now();
    final before = _pendingLocalEnrollments.length;
    _pendingLocalEnrollments.removeWhere(
      (_, record) => !current.isBefore(record.expiresAt),
    );
    final changesBefore = _pendingChanges.length;
    _pendingChanges.removeWhere(
      (_, record) => !current.isBefore(record.expiresAt),
    );
    if (before != _pendingLocalEnrollments.length ||
        changesBefore != _pendingChanges.length) {
      _persist();
    }
  }

  int get pendingLocalEnrollmentCount => _pendingLocalEnrollments.length;

  String _newSecret() {
    final bytes = List<int>.generate(32, (_) => _random.nextInt(256));
    return base64UrlEncode(bytes).replaceAll('=', '');
  }

  String _newCode() => (_random.nextInt(900000) + 100000).toString();

  String _digest(String value) => sha256.convert(utf8.encode(value)).toString();

  void _load() {
    final file = _storageFile;
    if (file == null || !file.existsSync()) return;
    try {
      final root = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      final verified = root['verified'] as Map<String, dynamic>? ?? const {};
      final pending =
          root['pendingLocalEnrollments'] as Map<String, dynamic>? ?? const {};
      final changes =
          root['pendingChanges'] as Map<String, dynamic>? ?? const {};
      for (final entry in verified.entries) {
        final value = entry.value as Map<String, dynamic>;
        _verified[entry.key] = _VerifiedRecoveryEmail(
          email: value['email'] as String,
          verifiedAt: DateTime.parse(value['verifiedAt'] as String).toUtc(),
        );
      }
      for (final entry in pending.entries) {
        final value = entry.value as Map<String, dynamic>;
        _pendingLocalEnrollments[entry.key] = RecoveryEmailLocalEnrollment(
          username: value['username'] as String,
          email: value['email'] as String,
          expiresAt: DateTime.parse(value['expiresAt'] as String).toUtc(),
        );
      }
      for (final entry in changes.entries) {
        final value = entry.value as Map<String, dynamic>;
        _pendingChanges[entry.key] = _PendingRecoveryEmailChange(
          username: value['username'] as String,
          currentEmail: value['currentEmail'] as String,
          newEmail: value['newEmail'] as String,
          currentEmailCodeDigest: value['currentEmailCodeDigest'] as String,
          newEmailCodeDigest: value['newEmailCodeDigest'] as String,
          expiresAt: DateTime.parse(value['expiresAt'] as String).toUtc(),
          attempts: value['attempts'] as int? ?? 0,
        );
      }
    } catch (_) {
      // A corrupt cache must fail closed. Existing recovery addresses are not
      // reconstructed from the insecure legacy mapping.
      _verified.clear();
      _pendingLocalEnrollments.clear();
      _pendingChanges.clear();
    }
  }

  void _persist() {
    final file = _storageFile;
    if (file == null) return;
    file.parent.createSync(recursive: true);
    final temporary = File('${file.path}.tmp');
    temporary.writeAsStringSync(
      jsonEncode({
        'version': 1,
        'verified': _verified.map(
          (username, record) => MapEntry(username, {
            'email': record.email,
            'verifiedAt': record.verifiedAt.toUtc().toIso8601String(),
          }),
        ),
        'pendingLocalEnrollments': _pendingLocalEnrollments.map(
          (digest, record) => MapEntry(digest, {
            'username': record.username,
            'email': record.email,
            'expiresAt': record.expiresAt.toUtc().toIso8601String(),
          }),
        ),
        'pendingChanges': _pendingChanges.map(
          (digest, record) => MapEntry(digest, {
            'username': record.username,
            'currentEmail': record.currentEmail,
            'newEmail': record.newEmail,
            'currentEmailCodeDigest': record.currentEmailCodeDigest,
            'newEmailCodeDigest': record.newEmailCodeDigest,
            'expiresAt': record.expiresAt.toUtc().toIso8601String(),
            'attempts': record.attempts,
          }),
        ),
      }),
      flush: true,
    );
    try {
      temporary.renameSync(file.path);
    } on FileSystemException {
      if (file.existsSync()) file.deleteSync();
      temporary.renameSync(file.path);
    }
  }
}

class _VerifiedRecoveryEmail {
  const _VerifiedRecoveryEmail({required this.email, required this.verifiedAt});

  final String email;
  final DateTime verifiedAt;
}

class RecoveryEmailLocalEnrollment {
  const RecoveryEmailLocalEnrollment({
    required this.username,
    required this.email,
    required this.expiresAt,
  });

  final String username;
  final String email;
  final DateTime expiresAt;
}

class RecoveryEmailChangeIssue {
  const RecoveryEmailChangeIssue({
    required this.transactionId,
    required this.currentEmailCode,
    required this.newEmailCode,
  });

  final String transactionId;
  final String currentEmailCode;
  final String newEmailCode;
}

class _PendingRecoveryEmailChange {
  _PendingRecoveryEmailChange({
    required this.username,
    required this.currentEmail,
    required this.newEmail,
    required this.currentEmailCodeDigest,
    required this.newEmailCodeDigest,
    required this.expiresAt,
    this.attempts = 0,
  });

  final String username;
  final String currentEmail;
  final String newEmail;
  final String currentEmailCodeDigest;
  final String newEmailCodeDigest;
  final DateTime expiresAt;
  int attempts;
}
