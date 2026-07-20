import 'package:flutter/foundation.dart';
import 'package:matrix/matrix.dart';

import 'matrix_service.dart';

class ChatArchiveService {
  ChatArchiveService(this._matrixService);

  static const String archivedTag = 'u.xmo.hidden';

  final MatrixService _matrixService;

  static bool isArchived(Room room) => room.tags.containsKey(archivedTag);

  Future<void> archive(Room room) async {
    await room.addTag(archivedTag);
    await _syncArchiveState(room.id);
  }

  Future<void> unarchive(Room room) async {
    await room.removeTag(archivedTag);
    await _syncArchiveState(room.id);
  }

  Future<void> _syncArchiveState(String roomId) async {
    try {
      await _matrixService.client.oneShotSync();
    } catch (error) {
      debugPrint('[ChatArchive] Sync refresh failed for $roomId: $error');
    }
  }
}
