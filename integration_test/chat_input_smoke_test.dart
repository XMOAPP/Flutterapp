import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:xmo/screens/matrix_chat/chat_input_bar.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('composer interaction works on an Android device', (
    tester,
  ) async {
    final controller = TextEditingController();
    var sent = false;
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          bottomNavigationBar: ChatInputBar(
            textController: controller,
            uploading: false,
            onSend: () => sent = true,
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

    await tester.enterText(find.byType(TextField), 'device smoke test');
    await tester.pump();
    expect(find.byKey(const ValueKey('send')), findsOneWidget);

    final sendButton = tester.widget<GestureDetector>(
      find.byKey(const ValueKey('send')),
    );
    sendButton.onTap!();
    expect(sent, isTrue);
    controller.dispose();
  });
}
