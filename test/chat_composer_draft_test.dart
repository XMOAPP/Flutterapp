import 'package:flutter_test/flutter_test.dart';
import 'package:xmo/screens/matrix_chat/controllers/chat_composer_controller.dart';
import 'package:xmo/services/message_draft_service.dart';

void main() {
  const userId = '@alice:example.org';
  const roomId = '!room:example.org';

  test('restores and persists a room-scoped draft', () async {
    final store = _MemoryDraftStore()
      ..values[_key(userId, roomId)] = 'saved draft';
    final controller = _controller(store);

    await controller.bindDraft(userId: userId, roomId: roomId);
    expect(controller.textController.text, 'saved draft');

    controller.textController.text = 'updated draft';
    await _settleDraftSave();
    expect(store.values[_key(userId, roomId)], 'updated draft');

    controller.dispose();
  });

  test('confirmed send removes the stored draft', () async {
    final store = _MemoryDraftStore();
    final controller = _controller(store);
    await controller.bindDraft(userId: userId, roomId: roomId);
    controller.textController.text = 'send me';

    expect(await controller.beginPendingSend('send me'), isTrue);
    expect(controller.textController.text, isEmpty);
    expect(store.values[_key(userId, roomId)], 'send me');

    await controller.confirmPendingSend();
    expect(store.values.containsKey(_key(userId, roomId)), isFalse);

    controller.dispose();
  });

  test('failed send restores and keeps the draft', () async {
    final store = _MemoryDraftStore();
    final controller = _controller(store);
    await controller.bindDraft(userId: userId, roomId: roomId);
    controller.textController.text = 'retry me';

    await controller.beginPendingSend('retry me');
    controller.restoreAfterFailedSend('retry me');
    await _settleDraftSave();

    expect(controller.textController.text, 'retry me');
    expect(store.values[_key(userId, roomId)], 'retry me');

    controller.dispose();
  });

  test('text typed during a send remains a draft after confirmation', () async {
    final store = _MemoryDraftStore();
    final controller = _controller(store);
    await controller.bindDraft(userId: userId, roomId: roomId);
    controller.textController.text = 'first message';

    await controller.beginPendingSend('first message');
    controller.textController.text = 'next message';
    await controller.confirmPendingSend();
    await _settleDraftSave();

    expect(controller.textController.text, 'next message');
    expect(store.values[_key(userId, roomId)], 'next message');

    controller.dispose();
  });
}

ChatComposerController _controller(MessageDraftStore store) {
  return ChatComposerController(
    draftStore: store,
    draftSaveDelay: Duration.zero,
  );
}

Future<void> _settleDraftSave() =>
    Future<void>.delayed(const Duration(milliseconds: 10));

String _key(String userId, String roomId) => '$userId|$roomId';

class _MemoryDraftStore implements MessageDraftStore {
  final Map<String, String> values = {};

  @override
  Future<String?> load({required String userId, required String roomId}) async {
    return values[_key(userId, roomId)];
  }

  @override
  Future<void> save({
    required String userId,
    required String roomId,
    required String text,
  }) async {
    values[_key(userId, roomId)] = text;
  }

  @override
  Future<void> delete({required String userId, required String roomId}) async {
    values.remove(_key(userId, roomId));
  }

  @override
  Future<void> clearAccount(String userId) async {
    values.removeWhere((key, _) => key.startsWith('$userId|'));
  }
}
