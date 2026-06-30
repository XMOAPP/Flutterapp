import 'package:flutter/foundation.dart';

class ReplyDraft {
  const ReplyDraft({
    required this.eventId,
    required this.senderName,
    required this.previewText,
    this.roomId,
  });

  final String eventId;
  final String senderName;
  final String previewText;
  final String? roomId;
}

class ReplyReactionController extends ChangeNotifier {
  ReplyDraft? _replyDraft;
  String? _highlightedEventId;

  ReplyDraft? get replyDraft => _replyDraft;
  String? get highlightedEventId => _highlightedEventId;

  void setReplyDraft(ReplyDraft draft) {
    _replyDraft = draft;
    notifyListeners();
  }

  void clearReplyDraft() {
    if (_replyDraft == null) return;
    _replyDraft = null;
    notifyListeners();
  }

  void highlightEvent(String eventId) {
    _highlightedEventId = eventId;
    notifyListeners();
  }

  void clearHighlight() {
    if (_highlightedEventId == null) return;
    _highlightedEventId = null;
    notifyListeners();
  }
}
