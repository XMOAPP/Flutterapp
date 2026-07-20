import 'package:flutter_test/flutter_test.dart';
import 'package:xmo/screens/matrix_chat/widgets/media_message_bubble.dart';
import 'package:xmo/screens/matrix_chat/widgets/message_reply_context.dart';
import 'package:xmo/screens/matrix_chat/widgets/text_file_bubble.dart';
import 'package:xmo/screens/matrix_chat_screen.dart';

void main() {
  test('reply transport and bubble APIs compile together', () {
    expect(MatrixChatScreen, isNotNull);
    expect(MediaMessageBubble, isNotNull);
    expect(TextOrFileMessageBubble, isNotNull);
    expect(matrixReplyEventId, isA<Function>());
    expect(hasMatrixReply, isA<Function>());
  });
}
