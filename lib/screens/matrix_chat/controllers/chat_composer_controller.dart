import 'package:flutter/widgets.dart';

/// Owns composer input resources independently from the chat screen lifecycle.
class ChatComposerController {
  final TextEditingController textController = TextEditingController();
  final FocusNode focusNode = FocusNode();

  void setInitialText(String? text) {
    if (text == null || text.isEmpty) return;
    textController.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }

  void dispose() {
    textController.dispose();
    focusNode.dispose();
  }
}
