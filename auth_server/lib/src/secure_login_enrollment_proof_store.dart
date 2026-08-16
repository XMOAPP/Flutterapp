import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';

class SecureLoginEnrollmentProofClaim {
  const SecureLoginEnrollmentProofClaim({
    required this.emailDigest,
    required this.expiresAt,
  });

  final String emailDigest;
  final DateTime expiresAt;
}

class _CompletedSecureLoginEnrollment {
  const _CompletedSecureLoginEnrollment({
    required this.emailDigest,
    required this.username,
    required this.expiresAt,
  });

  final String emailDigest;
  final String username;
  final DateTime expiresAt;
}

/// One-use proof store binding successful email verification to secure-login
/// provisioning. Only proof digests are retained by the server. When a
/// [storageFile] is supplied, pending and completed proofs survive restarts.
class SecureLoginEnrollmentProofStore {
  SecureLoginEnrollmentProofStore({
    this.ttl = const Duration(minutes: 5),
    File? storageFile,
    Random? random,
    DateTime Function()? now,
  })  : _random = random ?? Random.secure(),
        _now = now ?? (() => DateTime.now().toUtc()),
        _storageFile = storageFile {
    _load();
    prune();
  }

  final Duration ttl;
  final Random _random;
  final DateTime Function() _now;
  final File? _storageFile;
  final Map<String, SecureLoginEnrollmentProofClaim> _records = {};
  final Map<String, _CompletedSecureLoginEnrollment> _completed = {};

  String issue(String email) {
    prune();
    final bytes = List<int>.generate(32, (_) => _random.nextInt(256));
    final proof = base64UrlEncode(bytes).replaceAll('=', '');
    _records[_digest(proof)] = SecureLoginEnrollmentProofClaim(
      emailDigest: _digest(email),
      expiresAt: _now().add(ttl),
    );
    _persist();
    return proof;
  }

  SecureLoginEnrollmentProofClaim? claim({
    required String proof,
    required String email,
  }) {
    prune();
    if (proof.isEmpty) return null;
    final digest = _digest(proof);
    final record = _records.remove(digest);
    if (record == null) return null;
    if (record.emailDigest != _digest(email)) {
      _persist();
      return null;
    }
    // Deliberately leave the on-disk pending record until complete(). If the
    // process stops during the Authentik request, a retry can resume safely.
    return record;
  }

  void restore(String proof, SecureLoginEnrollmentProofClaim claim) {
    if (proof.isNotEmpty && _now().isBefore(claim.expiresAt)) {
      _records[_digest(proof)] = claim;
    }
  }

  void complete({
    required String proof,
    required SecureLoginEnrollmentProofClaim claim,
    required String username,
  }) {
    final digest = _digest(proof);
    _records.remove(digest);
    _completed[digest] = _CompletedSecureLoginEnrollment(
      emailDigest: claim.emailDigest,
      username: username,
      expiresAt: claim.expiresAt,
    );
    _persist();
  }

  bool wasCompleted({
    required String proof,
    required String email,
    required String username,
  }) {
    prune();
    final completed = _completed[_digest(proof)];
    return completed != null &&
        completed.emailDigest == _digest(email) &&
        completed.username == username;
  }

  void prune() {
    final current = _now();
    final recordsBefore = _records.length;
    final completedBefore = _completed.length;
    _records.removeWhere((_, record) => !current.isBefore(record.expiresAt));
    _completed.removeWhere(
      (_, record) => !current.isBefore(record.expiresAt),
    );
    if (recordsBefore != _records.length ||
        completedBefore != _completed.length) {
      _persist();
    }
  }

  int get length => _records.length;

  String _digest(String proof) => sha256.convert(utf8.encode(proof)).toString();

  void _load() {
    final file = _storageFile;
    if (file == null || !file.existsSync()) return;
    try {
      final root = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      final pending = root['pending'] as Map<String, dynamic>? ?? const {};
      final completed = root['completed'] as Map<String, dynamic>? ?? const {};
      for (final entry in pending.entries) {
        final value = entry.value as Map<String, dynamic>;
        _records[entry.key] = SecureLoginEnrollmentProofClaim(
          emailDigest: value['emailDigest'] as String,
          expiresAt: DateTime.parse(value['expiresAt'] as String).toUtc(),
        );
      }
      for (final entry in completed.entries) {
        final value = entry.value as Map<String, dynamic>;
        _completed[entry.key] = _CompletedSecureLoginEnrollment(
          emailDigest: value['emailDigest'] as String,
          username: value['username'] as String,
          expiresAt: DateTime.parse(value['expiresAt'] as String).toUtc(),
        );
      }
    } catch (_) {
      final quarantine = File(
        '${file.path}.corrupt.${DateTime.now().toUtc().millisecondsSinceEpoch}',
      );
      try {
        file.renameSync(quarantine.path);
      } catch (_) {
        // A corrupt proof cache may invalidate current registration attempts,
        // but must never prevent the authentication service from starting.
      }
      _records.clear();
      _completed.clear();
    }
  }

  void _persist() {
    final file = _storageFile;
    if (file == null) return;
    file.parent.createSync(recursive: true);
    final payload = jsonEncode({
      'version': 1,
      'pending': _records.map(
        (digest, record) => MapEntry(digest, {
          'emailDigest': record.emailDigest,
          'expiresAt': record.expiresAt.toUtc().toIso8601String(),
        }),
      ),
      'completed': _completed.map(
        (digest, record) => MapEntry(digest, {
          'emailDigest': record.emailDigest,
          'username': record.username,
          'expiresAt': record.expiresAt.toUtc().toIso8601String(),
        }),
      ),
    });
    final temporary = File('${file.path}.tmp');
    temporary.writeAsStringSync(payload, flush: true);
    try {
      temporary.renameSync(file.path);
    } on FileSystemException {
      if (file.existsSync()) file.deleteSync();
      temporary.renameSync(file.path);
    }
  }
}
