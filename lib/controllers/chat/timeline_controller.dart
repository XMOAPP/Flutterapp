import 'package:flutter/foundation.dart';

class ChatTimelineController extends ChangeNotifier {
  ChatTimelineController({required this.roomId});

  final String roomId;

  bool _isLoadingOlder = false;
  bool _isNearBottom = true;
  int _pendingNewMessages = 0;

  bool get isLoadingOlder => _isLoadingOlder;
  bool get isNearBottom => _isNearBottom;
  int get pendingNewMessages => _pendingNewMessages;

  void setLoadingOlder(bool value) {
    if (_isLoadingOlder == value) return;
    _isLoadingOlder = value;
    notifyListeners();
  }

  void setNearBottom(bool value) {
    if (_isNearBottom == value) return;
    _isNearBottom = value;
    if (value) {
      _pendingNewMessages = 0;
    }
    notifyListeners();
  }

  void incrementPendingNewMessages([int count = 1]) {
    if (_isNearBottom || count <= 0) return;
    _pendingNewMessages += count;
    notifyListeners();
  }

  void clearPendingNewMessages() {
    if (_pendingNewMessages == 0) return;
    _pendingNewMessages = 0;
    notifyListeners();
  }
}
