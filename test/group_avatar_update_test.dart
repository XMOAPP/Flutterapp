import 'package:flutter_test/flutter_test.dart';
import 'package:xmo/services/group_service.dart';

void main() {
  group('GroupService room avatar validation', () {
    test('maps supported image extensions to upload content types', () {
      expect(
        GroupService.avatarContentTypeForFileName('avatar.PNG'),
        'image/png',
      );
      expect(
        GroupService.avatarContentTypeForFileName('avatar.webp'),
        'image/webp',
      );
      expect(
        GroupService.avatarContentTypeForFileName('avatar.gif'),
        'image/gif',
      );
      expect(
        GroupService.avatarContentTypeForFileName('avatar.jpg'),
        'image/jpeg',
      );
    });

    test('accepts a valid Matrix content URI', () {
      expect(
        GroupService.parseAvatarMxcUrl('mxc://matrix.example/media-id'),
        Uri.parse('mxc://matrix.example/media-id'),
      );
    });

    test('rejects HTTP and incomplete Matrix content URIs', () {
      expect(
        () =>
            GroupService.parseAvatarMxcUrl('https://matrix.example/avatar.jpg'),
        throwsFormatException,
      );
      expect(
        () => GroupService.parseAvatarMxcUrl('mxc://matrix.example'),
        throwsFormatException,
      );
    });
  });
}
