import 'dart:io';

import 'package:test/test.dart';
import 'package:xmo_auth_server/src/endpoint_modules.dart';

Future<void> _noop(HttpRequest _) async {}

void main() {
  const module = AzureBlobEndpointModule(signUpload: _noop, download: _noop);

  test('matches authenticated Azure chunk route aliases', () {
    expect(
      module.handlesSignUpload('/auth/media/chunks/azure/sign-upload'),
      isTrue,
    );
    expect(module.handlesDownload('/auth/media/chunks/azure/download'), isTrue);
    expect(
      module.handlesDownload('/auth/otp/media/chunks/azure/download'),
      isTrue,
    );
    expect(
      module.handlesDownload('/auth/media/chunks/azure/sign-upload'),
      isFalse,
    );
  });
}
