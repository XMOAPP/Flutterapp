import 'dart:io';
import 'dart:math';

import 'package:test/test.dart';
import 'package:xmo_auth_server/src/secure_login_enrollment_proof_store.dart';

void main() {
  late DateTime now;
  late SecureLoginEnrollmentProofStore store;

  setUp(() {
    now = DateTime.utc(2026, 8, 8, 12);
    store = SecureLoginEnrollmentProofStore(
      ttl: const Duration(minutes: 5),
      random: Random(7),
      now: () => now,
    );
  });

  test('proof is bound to its verified email and can be used once', () {
    final proof = store.issue('person@example.com');

    expect(
      store.claim(proof: proof, email: 'other@example.com'),
      isNull,
    );
    expect(store.length, 0);

    final secondProof = store.issue('person@example.com');
    expect(
      store.claim(proof: secondProof, email: 'person@example.com'),
      isNotNull,
    );
    expect(
      store.claim(proof: secondProof, email: 'person@example.com'),
      isNull,
    );
  });

  test('expired proof cannot be claimed or restored', () {
    final proof = store.issue('person@example.com');
    now = now.add(const Duration(minutes: 6));

    expect(
      store.claim(proof: proof, email: 'person@example.com'),
      isNull,
    );
    expect(store.length, 0);
  });

  test('claimed proof can be restored after a transient provider failure', () {
    final proof = store.issue('person@example.com');
    final claim = store.claim(
      proof: proof,
      email: 'person@example.com',
    );
    expect(claim, isNotNull);

    store.restore(proof, claim!);

    expect(
      store.claim(proof: proof, email: 'person@example.com'),
      isNotNull,
    );
  });

  test('completed proof makes the same provisioning retry idempotent', () {
    final proof = store.issue('person@example.com');
    final claim = store.claim(
      proof: proof,
      email: 'person@example.com',
    )!;
    store.complete(proof: proof, claim: claim, username: 'hunter');

    expect(
      store.wasCompleted(
        proof: proof,
        email: 'person@example.com',
        username: 'hunter',
      ),
      isTrue,
    );
    expect(
      store.wasCompleted(
        proof: proof,
        email: 'person@example.com',
        username: 'other-user',
      ),
      isFalse,
    );
  });

  test('pending proof survives a server restart', () {
    final directory = Directory.systemTemp.createTempSync('xmo-proof-test-');
    addTearDown(() => directory.deleteSync(recursive: true));
    final file = File('${directory.path}/proofs.json');
    final first = SecureLoginEnrollmentProofStore(
      ttl: const Duration(minutes: 5),
      storageFile: file,
      random: Random(7),
      now: () => now,
    );
    final proof = first.issue('person@example.com');

    final restarted = SecureLoginEnrollmentProofStore(
      ttl: const Duration(minutes: 5),
      storageFile: file,
      random: Random(8),
      now: () => now,
    );

    expect(
      restarted.claim(proof: proof, email: 'person@example.com'),
      isNotNull,
    );
  });

  test('proof can resume after process stops while claim is in flight', () {
    final directory = Directory.systemTemp.createTempSync('xmo-proof-test-');
    addTearDown(() => directory.deleteSync(recursive: true));
    final file = File('${directory.path}/proofs.json');
    final first = SecureLoginEnrollmentProofStore(
      ttl: const Duration(minutes: 5),
      storageFile: file,
      random: Random(7),
      now: () => now,
    );
    final proof = first.issue('person@example.com');
    expect(
      first.claim(proof: proof, email: 'person@example.com'),
      isNotNull,
    );

    final restarted = SecureLoginEnrollmentProofStore(
      ttl: const Duration(minutes: 5),
      storageFile: file,
      random: Random(8),
      now: () => now,
    );

    expect(
      restarted.claim(proof: proof, email: 'person@example.com'),
      isNotNull,
    );
  });

  test('completed proof survives a server restart', () {
    final directory = Directory.systemTemp.createTempSync('xmo-proof-test-');
    addTearDown(() => directory.deleteSync(recursive: true));
    final file = File('${directory.path}/proofs.json');
    final first = SecureLoginEnrollmentProofStore(
      ttl: const Duration(minutes: 5),
      storageFile: file,
      random: Random(7),
      now: () => now,
    );
    final proof = first.issue('person@example.com');
    final claim = first.claim(
      proof: proof,
      email: 'person@example.com',
    )!;
    first.complete(proof: proof, claim: claim, username: 'hunter');

    final restarted = SecureLoginEnrollmentProofStore(
      ttl: const Duration(minutes: 5),
      storageFile: file,
      random: Random(8),
      now: () => now,
    );

    expect(
      restarted.wasCompleted(
        proof: proof,
        email: 'person@example.com',
        username: 'hunter',
      ),
      isTrue,
    );
  });
}
