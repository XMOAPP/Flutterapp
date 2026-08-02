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

  testWidgets('edit mode reuses composer without attachment or recording',
      (tester) async {
    final controller = TextEditingController(text: 'original');
    var confirmed = false;
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          bottomNavigationBar: ChatInputBar(
            textController: controller,
            uploading: false,
            editing: true,
            editingOriginalText: 'original',
            onSend: () => confirmed = true,
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

    expect(find.byIcon(Icons.add_circle_outline), findsNothing);
    expect(find.byKey(const ValueKey('record')), findsNothing);
    expect(find.byKey(const ValueKey('confirm-edit')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('confirm-edit')));
    expect(confirmed, isFalse);

    await tester.enterText(find.byType(TextField), 'changed');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('confirm-edit')));
    expect(confirmed, isTrue);

    controller.dispose();
  });

  testWidgets('chat input expands vertically and caps at six lines',
      (tester) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          bottomNavigationBar: ChatInputBar(
            textController: controller,
            uploading: false,
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

    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.minLines, 1);
    expect(field.maxLines, 6);
    expect(field.keyboardType, TextInputType.multiline);
    expect(field.textInputAction, TextInputAction.newline);

    final initialHeight = tester.getSize(find.byType(ChatInputBar)).height;
    await tester.enterText(find.byType(TextField), 'one\ntwo\nthree');
    await tester.pump();
    final expandedHeight = tester.getSize(find.byType(ChatInputBar)).height;
    expect(expandedHeight, greaterThan(initialHeight));

    await tester.enterText(
      find.byType(TextField),
      List.generate(10, (index) => 'line $index').join('\n'),
    );
    await tester.pump();
    final cappedHeight = tester.getSize(find.byType(ChatInputBar)).height;
    expect(cappedHeight, greaterThanOrEqualTo(expandedHeight));
    expect(cappedHeight, lessThan(220));
    expect(tester.takeException(), isNull);
  });
}
