/// Keeps reply state separate from the timeline presentation.
///
/// The generic types allow the controller to be reused without importing the
/// screen's private Matrix event and draft models.
class ChatReplyReactionController<TEvent, TPrivateReply> {
  TEvent? replyTo;
  TPrivateReply? privateReply;

  void beginReply(TEvent event) {
    replyTo = event;
    privateReply = null;
  }

  void beginPrivateReply(TPrivateReply draft) {
    privateReply = draft;
    replyTo = null;
  }

  void clearReply() => replyTo = null;

  void clearPrivateReply() => privateReply = null;
}
