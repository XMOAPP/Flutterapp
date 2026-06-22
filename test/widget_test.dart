import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xmo/screens/matrix_chat/chat_input_bar.dart';

void main() {
  testWidgets('chat input switches from recording to send when text is typed',
      (tester) async {
    final controller = TextEditingController();
    var didSend = false;
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          bottomNavigationBar: ChatInputBar(
            textController: controller,
            uploading: false,
            onSend: () => didSend = true,
            onShowEmojiPicker: () {},
            onShowAttachmentSheet: () {},
            onStartRecording: () {},
            onCancelRecording: () {},
            onToggleRecordingPause: () {},
            onStopAndSendRecording: () {},
          ),
        ),
      ),
    );

    expect(find.byKey(const ValueKey('record')), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'hello');
    await tester.pump();
    expect(find.byKey(const ValueKey('send')), findsOneWidget);

    final sendButton = tester.widget<GestureDetector>(
      find.byKey(const ValueKey('send')),
    );
    sendButton.onTap!();
    expect(didSend, isTrue);
    controller.dispose();
  });

  testWidgets('disabled chat input explains why it cannot send',
      (tester) async {
    final controller = TextEditingController();
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          bottomNavigationBar: ChatInputBar(
            textController: controller,
            uploading: false,
            enabled: false,
            disabledText: 'Only admins can post',
            onSend: () {},
            onShowEmojiPicker: () {},
            onShowAttachmentSheet: () {},
            onStartRecording: () {},
            onCancelRecording: () {},
            onToggleRecordingPause: () {},
            onStopAndSendRecording: () {},
          ),
        ),
      ),
    );

    expect(find.text('Only admins can post'), findsOneWidget);
    controller.dispose();
  });
}
