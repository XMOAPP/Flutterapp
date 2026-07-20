import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../../services/message_draft_service.dart';

/// Owns composer input resources independently from the chat screen lifecycle.
class ChatComposerController {
  ChatComposerController({
    MessageDraftStore? draftStore,
    Duration draftSaveDelay = const Duration(milliseconds: 450),
  })  : _draftStore = draftStore ?? MessageDraftService(),
        _draftSaveDelay = draftSaveDelay {
    textController.addListener(_handleTextChanged);
  }

  final TextEditingController textController = TextEditingController();
  final FocusNode focusNode = FocusNode();
  final MessageDraftStore _draftStore;
  final Duration _draftSaveDelay;

  Timer? _draftSaveTimer;
  String? _draftUserId;
  String? _draftRoomId;
  int _bindingGeneration = 0;
  bool _applyingDraft = false;
  bool _pendingSend = false;
  bool _disposed = false;

  bool get isApplyingDraft => _applyingDraft;

  Future<void> bindDraft({
    required String userId,
    required String roomId,
  }) async {
    if (_disposed || userId.isEmpty || roomId.isEmpty) return;
    final generation = ++_bindingGeneration;
    _draftUserId = userId;
    _draftRoomId = roomId;

    if (textController.text.isNotEmpty) {
      await _saveSafely(textController.text);
      return;
    }

    String? draft;
    try {
      draft = await _draftStore.load(userId: userId, roomId: roomId);
    } catch (_) {
      return;
    }
    if (_disposed || generation != _bindingGeneration || draft == null) return;
    if (textController.text.isNotEmpty) return;

    _applyingDraft = true;
    try {
      textController.value = TextEditingValue(
        text: draft,
        selection: TextSelection.collapsed(offset: draft.length),
      );
    } finally {
      _applyingDraft = false;
    }
  }

  void setInitialText(String? text) {
    if (text == null || text.isEmpty) return;
    textController.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }

  Future<bool> beginPendingSend(String text) async {
    if (_pendingSend || _disposed) return false;
    _pendingSend = true;
    _draftSaveTimer?.cancel();
    textController.clear();
    await _saveSafely(text);
    return true;
  }

  Future<void> confirmPendingSend() async {
    _pendingSend = false;
    _draftSaveTimer?.cancel();
    await _deleteSafely();
    if (textController.text.isNotEmpty) _handleTextChanged();
  }

  void restoreAfterFailedSend(String text) {
    _pendingSend = false;
    if (_disposed) return;
    if (textController.text.isEmpty) {
      textController.value = TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: text.length),
      );
    } else {
      _handleTextChanged();
    }
  }

  void _handleTextChanged() {
    if (_disposed || _applyingDraft || _pendingSend || !_hasDraftScope) return;
    _draftSaveTimer?.cancel();
    _draftSaveTimer = Timer(_draftSaveDelay, () {
      final text = textController.text;
      if (text.isEmpty) {
        unawaited(_deleteSafely());
      } else {
        unawaited(_saveSafely(text));
      }
    });
  }

  bool get _hasDraftScope =>
      _draftUserId?.isNotEmpty == true && _draftRoomId?.isNotEmpty == true;

  Future<void> _saveSafely(String text) async {
    final userId = _draftUserId;
    final roomId = _draftRoomId;
    if (userId == null || roomId == null || text.isEmpty) return;
    try {
      await _draftStore.save(userId: userId, roomId: roomId, text: text);
    } catch (_) {
      // Draft persistence must never block messaging.
    }
  }

  Future<void> _deleteSafely() async {
    final userId = _draftUserId;
    final roomId = _draftRoomId;
    if (userId == null || roomId == null) return;
    try {
      await _draftStore.delete(userId: userId, roomId: roomId);
    } catch (_) {
      // Draft persistence must never block messaging.
    }
  }

  void dispose() {
    if (_disposed) return;
    _draftSaveTimer?.cancel();
    if (!_pendingSend && textController.text.isNotEmpty) {
      unawaited(_saveSafely(textController.text));
    }
    _disposed = true;
    textController.removeListener(_handleTextChanged);
    textController.dispose();
    focusNode.dispose();
  }
}
