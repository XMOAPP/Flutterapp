import 'package:flutter/widgets.dart';

class ChatMessageComposerController extends ChangeNotifier {
  ChatMessageComposerController() {
    textController.addListener(_handleTextChanged);
  }

  final TextEditingController textController = TextEditingController();

  bool _hasText = false;

  bool get hasText => _hasText;
  String get text => textController.text;

  void insertText(String value) {
    final currentText = textController.text;
    final selection = textController.selection;
    final fallbackOffset = currentText.length;
    final rawStart = selection.isValid ? selection.start : fallbackOffset;
    final rawEnd = selection.isValid ? selection.end : fallbackOffset;
    final start = rawStart.clamp(0, currentText.length);
    final end = rawEnd.clamp(0, currentText.length);
    final lower = start < end ? start : end;
    final upper = start < end ? end : start;
    final nextText = currentText.replaceRange(lower, upper, value);

    textController.value = TextEditingValue(
      text: nextText,
      selection: TextSelection.collapsed(offset: lower + value.length),
    );
  }

  void clear() => textController.clear();

  void _handleTextChanged() {
    final nextHasText = textController.text.trim().isNotEmpty;
    if (_hasText == nextHasText) return;
    _hasText = nextHasText;
    notifyListeners();
  }

  @override
  void dispose() {
    textController.removeListener(_handleTextChanged);
    textController.dispose();
    super.dispose();
  }
}
