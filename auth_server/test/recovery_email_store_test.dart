import 'dart:io';
import 'dart:math';

import 'package:test/test.dart';
import 'package:xmo_auth_server/src/recovery_email_store.dart';

void main() {
  late DateTime now;
  late RecoveryEmailStore store;

  setUp(() {
    now = DateTime.utc(2026, 8, 8, 12);
    store = RecoveryEmailStore(
      ttl: const Duration(minutes: 5),
      random: Random(7),
      now: () => now,
    );
  });

  test('a local enrollment ticket is bound to one username and is one use', () {
    final ticket = store.issueLocalEnrollment(
      username: 'alice',
      email: 'alice@example.com',
    );

    expect(
      store.claimLocalEnrollment(ticket: ticket, username: 'mallory'),
      isNull,
    );
    expect(
      store.claimLocalEnrollment(ticket: ticket, username: 'alice')?.email,
      'alice@example.com',
    );

    final secondTicket = store.issueLocalEnrollment(
      username: 'alice',
      email: 'alice@example.com',
    );
    final enrollment = store.claimLocalEnrollment(
      ticket: secondTicket,
      username: 'alice',
    );
    expect(enrollment?.email, 'alice@example.com');
    expect(
      store.claimLocalEnrollment(ticket: secondTicket, username: 'alice'),
      isNull,
    );
  });

  test('expired tickets cannot enroll a recovery email', () {
    final ticket = store.issueLocalEnrollment(
      username: 'alice',
      email: 'alice@example.com',
    );
    now = now.add(const Duration(minutes: 6));

    expect(
      store.claimLocalEnrollment(ticket: ticket, username: 'alice'),
      isNull,
    );
  });

  test('verified recovery emails are explicit and removable', () {
    store.setVerified(username: 'alice', email: 'alice@example.com');

    expect(store.hasVerifiedEmail('alice', 'alice@example.com'), isTrue);
    expect(store.hasVerifiedEmail('alice', 'other@example.com'), isFalse);
    expect(store.removeVerified('alice'), 'alice@example.com');
    expect(store.verifiedEmailFor('alice'), isNull);
  });

  test('changing an email requires independent codes for both addresses', () {
    final issue = store.issueChange(
      username: 'alice',
      currentEmail: 'old@example.com',
      newEmail: 'new@example.com',
    );

    expect(
      store.claimChange(
        transactionId: issue.transactionId,
        username: 'alice',
        currentEmailCode: issue.currentEmailCode,
        newEmailCode: '000000',
      ),
      isNull,
    );
    expect(
      store.claimChange(
        transactionId: issue.transactionId,
        username: 'alice',
        currentEmailCode: issue.currentEmailCode,
        newEmailCode: issue.newEmailCode,
      ),
      'new@example.com',
    );
  });

  test('verified records and pending tickets survive restart', () {
    final directory = Directory.systemTemp.createTempSync('xmo-recovery-test-');
    addTearDown(() => directory.deleteSync(recursive: true));
    final file = File('${directory.path}/recovery.json');
    final first = RecoveryEmailStore(
      ttl: const Duration(minutes: 5),
      storageFile: file,
      random: Random(7),
      now: () => now,
    );
    first.setVerified(username: 'alice', email: 'alice@example.com');
    final ticket = first.issueLocalEnrollment(
      username: 'bob',
      email: 'bob@example.com',
    );

    final restarted = RecoveryEmailStore(
      ttl: const Duration(minutes: 5),
      storageFile: file,
      random: Random(8),
      now: () => now,
    );
    expect(restarted.verifiedEmailFor('alice'), 'alice@example.com');
    expect(
      restarted.claimLocalEnrollment(ticket: ticket, username: 'bob')?.email,
      'bob@example.com',
    );
  });
}
