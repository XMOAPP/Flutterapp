import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

class SecureLoginEnrollmentProofClaim {
  const SecureLoginEnrollmentProofClaim({
    required this.email,
    required this.expiresAt,
  });

  final String email;
  final DateTime expiresAt;
}

class _CompletedSecureLoginEnrollment {
  const _CompletedSecureLoginEnrollment({
    required this.email,
    required this.username,
    required this.expiresAt,
  });

  final String email;
  final String username;
  final DateTime expiresAt;
}

/// In-memory, one-use proof store binding successful email verification to
/// secure-login provisioning. Only proof digests are retained by the server.
class SecureLoginEnrollmentProofStore {
  SecureLoginEnrollmentProofStore({
    this.ttl = const Duration(minutes: 5),
    Random? random,
    DateTime Function()? now,
  })  : _random = random ?? Random.secure(),
        _now = now ?? (() => DateTime.now().toUtc());

  final Duration ttl;
  final Random _random;
  final DateTime Function() _now;
  final Map<String, SecureLoginEnrollmentProofClaim> _records = {};
  final Map<String, _CompletedSecureLoginEnrollment> _completed = {};

  String issue(String email) {
    prune();
    final bytes = List<int>.generate(32, (_) => _random.nextInt(256));
    final proof = base64UrlEncode(bytes).replaceAll('=', '');
    _records[_digest(proof)] = SecureLoginEnrollmentProofClaim(
      email: email,
      expiresAt: _now().add(ttl),
    );
    return proof;
  }

  SecureLoginEnrollmentProofClaim? claim({
    required String proof,
    required String email,
  }) {
    prune();
    if (proof.isEmpty) return null;
    final record = _records.remove(_digest(proof));
    if (record == null || record.email != email) return null;
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
    _completed[_digest(proof)] = _CompletedSecureLoginEnrollment(
      email: claim.email,
      username: username,
      expiresAt: claim.expiresAt,
    );
  }

  bool wasCompleted({
    required String proof,
    required String email,
    required String username,
  }) {
    prune();
    final completed = _completed[_digest(proof)];
    return completed != null &&
        completed.email == email &&
        completed.username == username;
  }

  void prune() {
    final current = _now();
    _records.removeWhere((_, record) => !current.isBefore(record.expiresAt));
    _completed.removeWhere(
      (_, record) => !current.isBefore(record.expiresAt),
    );
  }

  int get length => _records.length;

  String _digest(String proof) => sha256.convert(utf8.encode(proof)).toString();
}
