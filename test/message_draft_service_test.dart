import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:xmo/services/message_draft_service.dart';

void main() {
  late Directory tempDirectory;

  setUpAll(() async {
    tempDirectory = await Directory.systemTemp.createTemp('xmo_drafts_test_');
    Hive.init(tempDirectory.path);
  });

  tearDown(() async {
    if (Hive.isBoxOpen(MessageDraftService.boxName)) {
      await Hive.box<dynamic>(MessageDraftService.boxName).close();
    }
    await Hive.deleteBoxFromDisk(MessageDraftService.boxName);
  });

  tearDownAll(() async {
    await Hive.close();
    if (await tempDirectory.exists()) {
      await tempDirectory.delete(recursive: true);
    }
  });

  test('draft survives closing and reopening its Hive box', () async {
    const userId = '@alice:example.org';
    const roomId = '!one:example.org';
    final service = MessageDraftService();

    await service.save(userId: userId, roomId: roomId, text: 'hello');
    await Hive.box<dynamic>(MessageDraftService.boxName).close();

    expect(
      await MessageDraftService().load(userId: userId, roomId: roomId),
      'hello',
    );
  });

  test('drafts are isolated by account and room', () async {
    final service = MessageDraftService();
    await service.save(
      userId: '@alice:example.org',
      roomId: '!one:example.org',
      text: 'alice one',
    );
    await service.save(
      userId: '@alice:example.org',
      roomId: '!two:example.org',
      text: 'alice two',
    );
    await service.save(
      userId: '@bob:example.org',
      roomId: '!one:example.org',
      text: 'bob one',
    );

    await service.clearAccount('@alice:example.org');

    expect(
      await service.load(
        userId: '@alice:example.org',
        roomId: '!one:example.org',
      ),
      isNull,
    );
    expect(
      await service.load(
        userId: '@alice:example.org',
        roomId: '!two:example.org',
      ),
      isNull,
    );
    expect(
      await service.load(
        userId: '@bob:example.org',
        roomId: '!one:example.org',
      ),
      'bob one',
    );
  });
}
