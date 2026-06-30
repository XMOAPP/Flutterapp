import 'package:flutter_test/flutter_test.dart';
import 'package:xmo/services/e2ee_verification_checklist.dart';

void main() {
  test('Phase 3 production gate stays closed without live evidence', () {
    expect(E2eeVerificationChecklist.isProductionReady(const {}), isFalse);
    expect(
      E2eeVerificationChecklist.missingProductionEvidenceIds(const {}),
      containsAll([
        'xmo_xmo_text',
        'xmo_xmo_media',
        'xmo_element_text_media',
        'recovery_setup',
        'backup_restore_after_reinstall',
        'cross_signing_verification',
        'verified_device_key_requests',
      ]),
    );
  });

  test('Phase 3 production gate opens only when all blocking items pass', () {
    final evidence = {
      for (final item in E2eeVerificationChecklist.items)
        item.id: E2eeEvidenceStatus.passed,
    };

    expect(E2eeVerificationChecklist.isProductionReady(evidence), isTrue);
    expect(
      E2eeVerificationChecklist.missingProductionEvidenceIds(evidence),
      isEmpty,
    );
  });

  test('failed or blocked evidence is not accepted as production proof', () {
    final evidence = {
      for (final item in E2eeVerificationChecklist.items)
        item.id: E2eeEvidenceStatus.passed,
      'xmo_element_text_media': E2eeEvidenceStatus.failed,
      'verified_device_key_requests': E2eeEvidenceStatus.blocked,
    };

    expect(E2eeVerificationChecklist.isProductionReady(evidence), isFalse);
    expect(
      E2eeVerificationChecklist.missingProductionEvidenceIds(evidence),
      ['xmo_element_text_media', 'verified_device_key_requests'],
    );
  });
}
