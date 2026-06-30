import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xmo/screens/matrix_chat/chat_input_bar.dart';
import 'package:xmo/widgets/direct_chat/message_reactions.dart';

void main() {
  Future<void> pumpChatInput(
    WidgetTester tester, {
    required Size size,
    required TextEditingController controller,
    bool recording = false,
  }) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          bottomNavigationBar: ChatInputBar(
            textController: controller,
            uploading: false,
            recording: recording,
            recordingDuration: const Duration(seconds: 65),
            recordingWaveform: const [0.2, 0.6, 0.9, 0.4, 0.7],
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
  }

  testWidgets('reaction details chip keeps per-user metadata and taps',
      (tester) async {
    MessageReactionSummary? tapped;
    const summary = MessageReactionSummary(
      emoji: '👍',
      count: 2,
      reactedByMe: true,
      users: [
        ReactionUser(userId: '@me:example.org', displayName: 'Me'),
        ReactionUser(userId: '@alex:example.org', displayName: 'Alex'),
      ],
    );

    await tester.binding.setSurfaceSize(const Size(320, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.centerLeft,
            child: MessageReactions(
              reactions: const [summary],
              onTap: (reaction) => tapped = reaction,
            ),
          ),
        ),
      ),
    );

    expect(find.text('👍'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);

    await tester.tap(find.text('👍'));
    expect(tapped, same(summary));
    expect(tapped!.users.map((user) => user.userId), [
      '@me:example.org',
      '@alex:example.org',
    ]);
  });

  testWidgets('chat input renders on very narrow phones without overflow',
      (tester) async {
    final controller = TextEditingController(text: 'hello');
    addTearDown(controller.dispose);

    await pumpChatInput(
      tester,
      size: const Size(320, 640),
      controller: controller,
    );

    expect(tester.takeException(), isNull);
    expect(find.byKey(const ValueKey('send')), findsOneWidget);
  });

  testWidgets('recording input renders in landscape without overflow',
      (tester) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);

    await pumpChatInput(
      tester,
      size: const Size(640, 320),
      controller: controller,
      recording: true,
    );

    expect(tester.takeException(), isNull);
    expect(find.text('01:05'), findsOneWidget);
  });
}
