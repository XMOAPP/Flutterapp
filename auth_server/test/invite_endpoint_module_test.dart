import 'dart:io';

import 'package:test/test.dart';
import 'package:xmo_auth_server/src/endpoint_modules.dart';

Future<void> _noop(HttpRequest _) async {}

void main() {
  const module = InviteEndpointModule(
    create: _noop,
    list: _noop,
    revoke: _noop,
    preview: _noop,
    avatar: _noop,
    redeem: _noop,
  );

  const token = 'abcdefghijklmnopqrstuvwxyz0123456789ABCDEFG';

  test('matches invite management route aliases', () {
    expect(module.handlesCreate('/invites/create'), isTrue);
    expect(module.handlesCreate('/auth/invites/create'), isTrue);
    expect(module.handlesCreate('/auth/otp/invites/create'), isTrue);
    expect(module.handlesList('/auth/otp/invites/list'), isTrue);
    expect(module.handlesRevoke('/auth/otp/invites/revoke'), isTrue);
  });

  test('extracts public invite tokens from supported route aliases', () {
    for (final prefix in const [
      '/invites/',
      '/auth/invites/',
      '/auth/otp/invites/',
    ]) {
      final previewPath = '$prefix$token/preview';
      final avatarPath = '$prefix$token/avatar';
      final redeemPath = '$prefix$token/redeem';
      expect(module.handlesPreview(previewPath), isTrue);
      expect(module.handlesAvatar(avatarPath), isTrue);
      expect(module.handlesRedeem(redeemPath), isTrue);
      expect(InviteEndpointModule.tokenFromPreviewPath(previewPath), token);
      expect(InviteEndpointModule.tokenFromAvatarPath(avatarPath), token);
      expect(InviteEndpointModule.tokenFromRedeemPath(redeemPath), token);
    }
  });

  test('rejects malformed token routes', () {
    expect(module.handlesPreview('/invites//preview'), isFalse);
    expect(module.handlesPreview('/invites/a/b/preview'), isFalse);
    expect(module.handlesAvatar('/invites/$token/preview'), isFalse);
    expect(module.handlesAvatar('/other/$token/avatar'), isFalse);
    expect(module.handlesRedeem('/invites/$token/preview'), isFalse);
    expect(module.handlesRedeem('/other/$token/redeem'), isFalse);
  });
}
