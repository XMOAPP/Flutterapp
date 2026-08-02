enum E2eeEvidenceStatus { pending, passed, failed, blocked }

class E2eeVerificationItem {
  final String id;
  final String title;
  final String objective;
  final List<String> requiredEvidence;
  final bool blocksProductionClaim;

  const E2eeVerificationItem({
    required this.id,
    required this.title,
    required this.objective,
    required this.requiredEvidence,
    this.blocksProductionClaim = true,
  });
}

class E2eeVerificationChecklist {
  const E2eeVerificationChecklist._();

  static const List<E2eeVerificationItem> items = [
    E2eeVerificationItem(
      id: 'xmo_xmo_text',
      title: 'XMO to XMO encrypted text',
      objective:
          'Two independent XMO Android devices exchange text in a private encrypted room.',
      requiredEvidence: [
        'Device A and B user IDs plus device IDs',
        'Room ID with m.room.encryption state event',
        'Event IDs for messages sent in both directions',
        'Screenshot or log showing both devices decrypted the messages',
      ],
    ),
    E2eeVerificationItem(
      id: 'xmo_xmo_media',
      title: 'XMO to XMO encrypted media',
      objective:
          'Two XMO devices exchange encrypted image, video, audio, and file events.',
      requiredEvidence: [
        'Event IDs for each media type',
        'Event content contains file or thumbnail_file, not plaintext media URL',
        'Both devices can preview and download each attachment',
      ],
    ),
    E2eeVerificationItem(
      id: 'xmo_element_text_media',
      title: 'XMO to Element interop',
      objective:
          'XMO and Element exchange encrypted text and media in the same room.',
      requiredEvidence: [
        'Element version and platform',
        'Room ID with encryption enabled before first message',
        'Message and media event IDs that decrypt on both clients',
      ],
    ),
    E2eeVerificationItem(
      id: 'recovery_setup',
      title: 'Recovery and key backup setup',
      objective:
          'XMO creates or unlocks SSSS, cross-signing, and online key backup.',
      requiredEvidence: [
        'Recovery key or passphrase flow completed',
        'Security screen shows cross-signing ready',
        'Security screen shows key backup ready',
      ],
    ),
    E2eeVerificationItem(
      id: 'backup_restore_after_reinstall',
      title: 'Backup restore after reinstall',
      objective:
          'A reinstalled XMO device restores keys and decrypts old encrypted history.',
      requiredEvidence: [
        'Device was uninstalled or app data was cleared',
        'Recovery unlock completed after reinstall',
        'Old text and media event IDs decrypt after restore',
      ],
    ),
    E2eeVerificationItem(
      id: 'cross_signing_verification',
      title: 'Cross-signing reliability',
      objective:
          'Existing verified session trusts the new session after verification.',
      requiredEvidence: [
        'Before and after device trust state for both sessions',
        'Cross-signing cached state after app restart',
        'No unexpected unverified-device warnings for verified sessions',
      ],
    ),
    E2eeVerificationItem(
      id: 'verified_device_key_requests',
      title: 'Verified-device key requests',
      objective:
          'A device missing message keys requests and receives them from a verified device.',
      requiredEvidence: [
        'Missing-key message or withheld-key state before request',
        'Request keys action completed',
        'Previously undecryptable event decrypts without room rejoin',
      ],
    ),
    E2eeVerificationItem(
      id: 'vodozemac_rust_engine',
      title: 'Vodozemac Rust E2EE engine status',
      objective:
          'App initializes the Rust-backed Vodozemac Olm and Megolm cryptographic ratchets at startup.',
      requiredEvidence: [
        'Vodozemac.init() executed successfully during app startup',
        'Security status screen displays Rust E2EE engine active',
        'Olm 1:1 and Megolm group ratchets operate using Vodozemac native crypto',
      ],
    ),
  ];

  static Iterable<E2eeVerificationItem> get blockingItems =>
      items.where((item) => item.blocksProductionClaim);

  static bool isProductionReady(Map<String, E2eeEvidenceStatus> evidence) {
    return blockingItems.every(
      (item) => evidence[item.id] == E2eeEvidenceStatus.passed,
    );
  }

  static List<String> missingProductionEvidenceIds(
    Map<String, E2eeEvidenceStatus> evidence,
  ) {
    return blockingItems
        .where((item) => evidence[item.id] != E2eeEvidenceStatus.passed)
        .map((item) => item.id)
        .toList(growable: false);
  }
}
