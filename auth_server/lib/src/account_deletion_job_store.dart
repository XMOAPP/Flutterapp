import 'dart:convert';
import 'dart:io';

enum AccountDeletionPhase {
  pending,
  mediaDeleted,
  synapseDeactivated,
  authentikDeleted,
  recordsPurged,
  complete,
}

class AccountDeletionJob {
  const AccountDeletionJob({
    required this.userId,
    required this.username,
    required this.phase,
    required this.updatedAt,
    this.lastError,
  });

  final String userId;
  final String username;
  final AccountDeletionPhase phase;
  final DateTime updatedAt;
  final String? lastError;

  bool get isComplete => phase == AccountDeletionPhase.complete;

  AccountDeletionJob copyWith({
    AccountDeletionPhase? phase,
    DateTime? updatedAt,
    String? lastError,
    bool clearError = false,
  }) {
    return AccountDeletionJob(
      userId: userId,
      username: username,
      phase: phase ?? this.phase,
      updatedAt: updatedAt ?? this.updatedAt,
      lastError: clearError ? null : lastError ?? this.lastError,
    );
  }
}

/// Durable progress for the cross-service account deletion workflow.
///
/// A completed job is retained briefly so repeated requests remain idempotent.
class AccountDeletionJobStore {
  AccountDeletionJobStore({
    required File storageFile,
    DateTime Function()? now,
    this.completedRetention = const Duration(days: 30),
  })  : _storageFile = storageFile,
        _now = now ?? (() => DateTime.now().toUtc()) {
    _load();
    prune();
  }

  final File _storageFile;
  final DateTime Function() _now;
  final Duration completedRetention;
  final Map<String, AccountDeletionJob> _jobs = {};

  AccountDeletionJob begin({
    required String userId,
    required String username,
  }) {
    final existing = _jobs[userId];
    if (existing != null) return existing;
    final job = AccountDeletionJob(
      userId: userId,
      username: username,
      phase: AccountDeletionPhase.pending,
      updatedAt: _now(),
    );
    _jobs[userId] = job;
    _persist();
    return job;
  }

  AccountDeletionJob advance(
    String userId,
    AccountDeletionPhase phase,
  ) {
    final current = _jobs[userId];
    if (current == null) {
      throw StateError('Account deletion job does not exist');
    }
    if (phase.index < current.phase.index) return current;
    final updated = current.copyWith(
      phase: phase,
      updatedAt: _now(),
      clearError: true,
    );
    _jobs[userId] = updated;
    _persist();
    return updated;
  }

  void recordFailure(String userId, Object error) {
    final current = _jobs[userId];
    if (current == null) return;
    _jobs[userId] = current.copyWith(
      updatedAt: _now(),
      lastError: error.toString(),
    );
    _persist();
  }

  AccountDeletionJob? get(String userId) => _jobs[userId];

  List<AccountDeletionJob> get pending =>
      _jobs.values.where((job) => !job.isComplete).toList(growable: false);

  void prune() {
    final cutoff = _now().subtract(completedRetention);
    final before = _jobs.length;
    _jobs.removeWhere(
      (_, job) => job.isComplete && job.updatedAt.isBefore(cutoff),
    );
    if (before != _jobs.length) _persist();
  }

  void _load() {
    if (!_storageFile.existsSync()) return;
    try {
      final root = jsonDecode(_storageFile.readAsStringSync());
      if (root is! Map<String, dynamic>) return;
      final jobs = root['jobs'];
      if (jobs is! Map<String, dynamic>) return;
      for (final entry in jobs.entries) {
        final value = entry.value;
        if (value is! Map<String, dynamic>) continue;
        final phaseName = value['phase']?.toString() ?? '';
        final phase = AccountDeletionPhase.values.where(
          (candidate) => candidate.name == phaseName,
        );
        if (phase.isEmpty) continue;
        _jobs[entry.key] = AccountDeletionJob(
          userId: value['userId']?.toString() ?? entry.key,
          username: value['username']?.toString() ?? '',
          phase: phase.first,
          updatedAt: DateTime.parse(value['updatedAt'].toString()).toUtc(),
          lastError: value['lastError']?.toString(),
        );
      }
    } catch (_) {
      final quarantine = File(
        '${_storageFile.path}.corrupt.'
        '${DateTime.now().toUtc().millisecondsSinceEpoch}',
      );
      try {
        _storageFile.renameSync(quarantine.path);
      } catch (_) {
        // A corrupt job file must not prevent the auth service from starting.
      }
      _jobs.clear();
    }
  }

  void _persist() {
    _storageFile.parent.createSync(recursive: true);
    final payload = jsonEncode({
      'version': 1,
      'jobs': _jobs.map(
        (key, job) => MapEntry(key, {
          'userId': job.userId,
          'username': job.username,
          'phase': job.phase.name,
          'updatedAt': job.updatedAt.toUtc().toIso8601String(),
          if (job.lastError != null) 'lastError': job.lastError,
        }),
      ),
    });
    final temporary = File('${_storageFile.path}.tmp');
    temporary.writeAsStringSync(payload, flush: true);
    try {
      temporary.renameSync(_storageFile.path);
    } on FileSystemException {
      if (_storageFile.existsSync()) _storageFile.deleteSync();
      temporary.renameSync(_storageFile.path);
    }
  }
}
