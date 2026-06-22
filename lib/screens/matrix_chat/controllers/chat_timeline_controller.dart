/// Small state holder for timeline loading and jump-to-latest behavior.
class ChatTimelineController {
  bool loading = true;
  bool loadingHistory = false;
  bool historyExhausted = false;
  bool showJumpToLatestButton = false;
  int newMessagesBelowCount = 0;
  bool scrollToBottomScheduled = false;

  void clearNewMessagesBelow() {
    showJumpToLatestButton = false;
    newMessagesBelowCount = 0;
  }

  void dispose() {}
}
