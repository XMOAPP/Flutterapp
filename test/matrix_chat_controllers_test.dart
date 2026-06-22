import 'package:flutter_test/flutter_test.dart';
import 'package:xmo/screens/matrix_chat/controllers/chat_call_coordinator.dart';
import 'package:xmo/screens/matrix_chat/controllers/chat_composer_controller.dart';
import 'package:xmo/screens/matrix_chat/controllers/chat_reply_reaction_controller.dart';
import 'package:xmo/screens/matrix_chat/controllers/chat_timeline_controller.dart';
import 'package:xmo/screens/matrix_chat/controllers/chat_transfer_controller.dart';

void main() {
  test('composer initializes text with a collapsed caret', () {
    final controller = ChatComposerController();
    controller.setInitialText('hello');

    expect(controller.textController.text, 'hello');
    expect(controller.textController.selection.baseOffset, 5);
    controller.dispose();
  });

  test('reply controller keeps normal and private replies exclusive', () {
    final controller = ChatReplyReactionController<String, int>();
    controller.beginReply('event');
    expect(controller.replyTo, 'event');
    expect(controller.privateReply, isNull);

    controller.beginPrivateReply(42);
    expect(controller.replyTo, isNull);
    expect(controller.privateReply, 42);
  });

  test('timeline controller clears jump and unread state together', () {
    final controller = ChatTimelineController()
      ..showJumpToLatestButton = true
      ..newMessagesBelowCount = 7;
    controller.clearNewMessagesBelow();

    expect(controller.showJumpToLatestButton, isFalse);
    expect(controller.newMessagesBelowCount, 0);
  });

  test('transfer and call controllers retain only screen-local UI state', () {
    final transfers = ChatTransferController<String, String>();
    transfers.uploads.add('upload');
    transfers.cancel('upload');
    expect(transfers.hasPendingWork, isTrue);
    expect(transfers.isCancelled('upload'), isTrue);

    final calls = ChatCallCoordinator();
    calls.dismiss('call-1');
    expect(calls.isDismissed('call-1'), isTrue);
  });
}
