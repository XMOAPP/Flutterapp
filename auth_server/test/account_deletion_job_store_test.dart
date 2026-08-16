import 'dart:io';

import 'package:test/test.dart';
import 'package:xmo_auth_server/src/account_deletion_job_store.dart';

void main() {
  late Directory directory;
  late File storageFile;
  var now = DateTime.utc(2026, 8, 11, 12);

  setUp(() {
    directory = Directory.systemTemp.createTempSync('xmo-deletion-jobs-');
    storageFile = File('${directory.path}/jobs.json');
  });

  tearDown(() {
    if (directory.existsSync()) directory.deleteSync(recursive: true);
  });

  AccountDeletionJobStore createStore() => AccountDeletionJobStore(
        storageFile: storageFile,
        now: () => now,
      );

  test('persists phase progress so deletion can resume after restart', () {
    final store = createStore();
    store.begin(
      userId: '@alice:example.test',
      username: 'alice',
    );
    store.advance(
      '@alice:example.test',
      AccountDeletionPhase.synapseDeactivated,
    );

    final restored = createStore().get('@alice:example.test');
    expect(restored, isNotNull);
    expect(restored!.username, 'alice');
    expect(restored.phase, AccountDeletionPhase.synapseDeactivated);
    expect(restored.lastError, isNull);
  });

  test('records failure without losing the last completed phase', () {
    final store = createStore();
    store.begin(userId: '@bob:example.test', username: 'bob');
    store.advance(
      '@bob:example.test',
      AccountDeletionPhase.mediaDeleted,
    );
    store.recordFailure('@bob:example.test', StateError('offline'));

    final restored = createStore().get('@bob:example.test');
    expect(restored!.phase, AccountDeletionPhase.mediaDeleted);
    expect(restored.lastError, contains('offline'));
    expect(createStore().pending, hasLength(1));
  });

  test('repeated begin is idempotent and completed jobs are retained', () {
    final store = createStore();
    final first = store.begin(
      userId: '@carol:example.test',
      username: 'carol',
    );
    final second = store.begin(
      userId: '@carol:example.test',
      username: 'changed',
    );
    expect(second.username, first.username);

    store.advance('@carol:example.test', AccountDeletionPhase.complete);
    expect(createStore().get('@carol:example.test')!.isComplete, isTrue);
    expect(createStore().pending, isEmpty);
  });

  test('prunes completed jobs after the retention period', () {
    final store = createStore();
    store.begin(userId: '@dave:example.test', username: 'dave');
    store.advance('@dave:example.test', AccountDeletionPhase.complete);

    now = now.add(const Duration(days: 31));
    expect(createStore().get('@dave:example.test'), isNull);
  });
}
