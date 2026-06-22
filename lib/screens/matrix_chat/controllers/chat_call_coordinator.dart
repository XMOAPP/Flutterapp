/// Per-chat UI state for group-call banner dismissal.
class ChatCallCoordinator {
  final Set<String> dismissedGroupCallBannerIds = <String>{};

  bool isDismissed(String callId) =>
      dismissedGroupCallBannerIds.contains(callId);

  void dismiss(String callId) => dismissedGroupCallBannerIds.add(callId);
}
