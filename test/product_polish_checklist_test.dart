import 'package:flutter_test/flutter_test.dart';
import 'package:xmo/services/product_polish_checklist.dart';

void main() {
  test('Phase 8 beta gate stays closed without product QA evidence', () {
    expect(ProductPolishChecklist.isBetaReady(const {}), isFalse);
    expect(
      ProductPolishChecklist.missingBetaEvidenceIds(const {}),
      containsAll([
        'reaction_details',
        'polls',
        'link_previews',
        'stories',
        'app_lock',
        'device_sessions',
        'responsive_qa',
      ]),
    );
  });

  test('Phase 8 beta gate opens only when all blocking items pass', () {
    final evidence = {
      for (final item in ProductPolishChecklist.items)
        item.id: ProductPolishEvidenceStatus.passed,
    };

    expect(ProductPolishChecklist.isBetaReady(evidence), isTrue);
    expect(ProductPolishChecklist.missingBetaEvidenceIds(evidence), isEmpty);
  });

  test('failed or blocked product QA is not accepted as beta proof', () {
    final evidence = {
      for (final item in ProductPolishChecklist.items)
        item.id: ProductPolishEvidenceStatus.passed,
      'stories': ProductPolishEvidenceStatus.failed,
      'responsive_qa': ProductPolishEvidenceStatus.blocked,
    };

    expect(ProductPolishChecklist.isBetaReady(evidence), isFalse);
    expect(ProductPolishChecklist.missingBetaEvidenceIds(evidence), [
      'stories',
      'responsive_qa',
    ]);
  });
}
