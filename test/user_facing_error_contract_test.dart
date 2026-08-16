import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('UI source does not contain the production homeserver hostname', () {
    const privateHost = 'xmo-matrix.centralindia.cloudapp.azure.com';
    final uiRoots = [Directory('lib/screens'), Directory('lib/widgets')];
    final offenders = <String>[];

    for (final root in uiRoots) {
      for (final entity in root.listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        if (entity.readAsStringSync().contains(privateHost)) {
          offenders.add(entity.path);
        }
      }
    }

    expect(
      offenders,
      isEmpty,
      reason: 'Internal service hosts must never be embedded in UI source.',
    );
  });

  test('shared error display applies the user-facing sanitizer', () {
    final source = File(
      'lib/widgets/common/error_display.dart',
    ).readAsStringSync();

    expect(source, contains('safeUserFacingText(error!)'));
  });

  test('persisted upload errors are sanitized before display', () {
    for (final path in [
      'lib/services/transfer_queue_service.dart',
      'lib/services/story_upload_queue_service.dart',
    ]) {
      final source = File(path).readAsStringSync();
      expect(source, contains('userFacingError('), reason: path);
      expect(source, isNot(contains("error: json['error'] as String?")));
    }
  });
}
