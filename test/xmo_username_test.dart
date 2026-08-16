import 'package:flutter_test/flutter_test.dart';
import 'package:xmo/utils/xmo_username.dart';

void main() {
  test('XMO usernames accept lowercase letters and numbers only', () {
    expect(isValidXmoUsername('alice01'), isTrue);
    expect(isValidXmoUsername('Alice01'), isFalse);
    expect(isValidXmoUsername('alice_01'), isFalse);
    expect(isValidXmoUsername('alice-01'), isFalse);
  });

  test('username formatter lowercases and removes disallowed characters', () {
    final value = xmoUsernameInputFormatters().fold<TextEditingValue>(
      const TextEditingValue(text: 'Alice_01-!'),
      (current, formatter) =>
          formatter.formatEditUpdate(const TextEditingValue(), current),
    );

    expect(value.text, 'alice01');
  });
}
