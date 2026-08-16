enum ProductPolishEvidenceStatus { pending, passed, failed, blocked }

class ProductPolishItem {
  final String id;
  final String title;
  final String objective;
  final List<String> requiredEvidence;
  final bool blocksBetaClaim;

  const ProductPolishItem({
    required this.id,
    required this.title,
    required this.objective,
    required this.requiredEvidence,
    this.blocksBetaClaim = true,
  });
}

class ProductPolishChecklist {
  const ProductPolishChecklist._();

  static const List<ProductPolishItem> items = [
    ProductPolishItem(
      id: 'reaction_details',
      title: 'Reaction details per user',
      objective:
          'Reaction chips open a details sheet showing each reacting user and allow the current user to remove their own reaction.',
      requiredEvidence: [
        'At least two users react with the same emoji',
        'Details sheet lists display names without clipping',
        'Current user removal updates the message reaction count',
      ],
    ),
    ProductPolishItem(
      id: 'polls',
      title: 'Poll creation and voting',
      objective:
          'Polls render, accept a vote, update counts, and remain readable on narrow screens.',
      requiredEvidence: [
        'Poll sent from XMO and visible after app restart',
        'Vote count changes once per voter',
        'Long question and option labels truncate cleanly',
      ],
    ),
    ProductPolishItem(
      id: 'link_previews',
      title: 'Link previews',
      objective:
          'Links generate previews with title, host/site, optional image, body text, and external open action.',
      requiredEvidence: [
        'Plain text URL creates a preview',
        'Image and no-image previews both render',
        'Tap opens the expected URL',
      ],
    ),
    ProductPolishItem(
      id: 'stories',
      title: 'Stories, replies, and reactions',
      objective:
          'Text, image, and video stories can be created, viewed, replied to, reacted to, and deleted.',
      requiredEvidence: [
        'Story view state persists after restart',
        'Reply arrives as a direct message',
        'Reaction arrives as a direct message',
      ],
    ),
    ProductPolishItem(
      id: 'app_lock',
      title: 'App lock',
      objective:
          'PIN and biometric app lock behave correctly across foreground, background, timeout, and restart.',
      requiredEvidence: [
        'Enable, unlock, timeout lock, lock now, and disable flows pass',
        'Failed PIN attempts trigger temporary blocking',
        'Settings are scoped to the signed-in user',
      ],
    ),
    ProductPolishItem(
      id: 'device_sessions',
      title: 'Device and session management',
      objective:
          'Device list, current-device label, verification state, rename, and delete flows work reliably.',
      requiredEvidence: [
        'Current device is sorted first',
        'Verified state matches XMO device keys',
        'Delete device handles reauthentication when required',
      ],
    ),
    ProductPolishItem(
      id: 'responsive_qa',
      title: 'Responsive behavior',
      objective:
          'Core screens remain usable on small phones, landscape, and Android split screen.',
      requiredEvidence: [
        'Chat, settings, stories, calls, and media preview checked at 320 px width',
        'Landscape pass on a physical Android device',
        'Split-screen pass with no clipped primary controls',
      ],
    ),
  ];

  static Iterable<ProductPolishItem> get blockingItems =>
      items.where((item) => item.blocksBetaClaim);

  static bool isBetaReady(Map<String, ProductPolishEvidenceStatus> evidence) {
    return blockingItems.every(
      (item) => evidence[item.id] == ProductPolishEvidenceStatus.passed,
    );
  }

  static List<String> missingBetaEvidenceIds(
    Map<String, ProductPolishEvidenceStatus> evidence,
  ) {
    return blockingItems
        .where(
          (item) => evidence[item.id] != ProductPolishEvidenceStatus.passed,
        )
        .map((item) => item.id)
        .toList(growable: false);
  }
}
