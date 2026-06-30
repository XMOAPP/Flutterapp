import 'package:flutter/foundation.dart';

enum ChatCallUiState { idle, incoming, outgoing, active, reconnecting }

class ChatCallCoordinator extends ChangeNotifier {
  ChatCallUiState _state = ChatCallUiState.idle;
  String? _callId;
  bool _isGroupCall = false;

  ChatCallUiState get state => _state;
  String? get callId => _callId;
  bool get isGroupCall => _isGroupCall;
  bool get hasCall => _state != ChatCallUiState.idle;

  void update({
    required ChatCallUiState state,
    String? callId,
    bool isGroupCall = false,
  }) {
    _state = state;
    _callId = callId;
    _isGroupCall = isGroupCall;
    notifyListeners();
  }

  void clear() {
    if (_state == ChatCallUiState.idle && _callId == null && !_isGroupCall) {
      return;
    }
    _state = ChatCallUiState.idle;
    _callId = null;
    _isGroupCall = false;
    notifyListeners();
  }
}
