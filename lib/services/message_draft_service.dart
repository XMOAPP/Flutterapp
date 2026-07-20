import 'dart:convert';

import 'package:hive_flutter/hive_flutter.dart';

abstract class MessageDraftStore {
  Future<String?> load({required String userId, required String roomId});

  Future<void> save({
    required String userId,
    required String roomId,
    required String text,
  });

  Future<void> delete({required String userId, required String roomId});

  Future<void> clearAccount(String userId);
}

class MessageDraftService implements MessageDraftStore {
  static const String boxName = 'xmo_message_drafts';
  static Future<Box<dynamic>>? _openingBox;

  Future<Box<dynamic>> _box() async {
    if (Hive.isBoxOpen(boxName)) return Hive.box<dynamic>(boxName);
    final opening = _openingBox;
    if (opening != null) return opening;

    final future = Hive.openBox<dynamic>(boxName);
    _openingBox = future;
    try {
      return await future;
    } finally {
      _openingBox = null;
    }
  }

  @override
  Future<String?> load({
    required String userId,
    required String roomId,
  }) async {
    if (!_validScope(userId, roomId)) return null;
    final value = (await _box()).get(_key(userId, roomId));
    if (value is String) return value.isEmpty ? null : value;
    if (value is! Map) return null;
    final text = value['text'];
    return text is String && text.isNotEmpty ? text : null;
  }

  @override
  Future<void> save({
    required String userId,
    required String roomId,
    required String text,
  }) async {
    if (!_validScope(userId, roomId)) return;
    if (text.isEmpty) {
      await delete(userId: userId, roomId: roomId);
      return;
    }
    await (await _box()).put(_key(userId, roomId), {
      'text': text,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    });
  }

  @override
  Future<void> delete({
    required String userId,
    required String roomId,
  }) async {
    if (!_validScope(userId, roomId)) return;
    await (await _box()).delete(_key(userId, roomId));
  }

  @override
  Future<void> clearAccount(String userId) async {
    if (userId.trim().isEmpty) return;
    final box = await _box();
    final keys = box.keys.where((key) {
      if (key is! String) return false;
      try {
        final scope = jsonDecode(key);
        return scope is List && scope.length == 2 && scope.first == userId;
      } catch (_) {
        return false;
      }
    }).toList(growable: false);
    if (keys.isNotEmpty) await box.deleteAll(keys);
  }

  bool _validScope(String userId, String roomId) =>
      userId.trim().isNotEmpty && roomId.trim().isNotEmpty;

  String _key(String userId, String roomId) => jsonEncode([userId, roomId]);
}
