import 'package:flutter/services.dart';

/// XMO account names are intentionally simple so they work consistently in
/// Matrix localparts, Authentik identities, and wallet-signature challenges.
final RegExp xmoUsernamePattern = RegExp(r'^[a-z0-9]+$');
final RegExp _xmoUsernameAllowedCharacters = RegExp(r'[a-z0-9]');

bool isValidXmoUsername(String value) => xmoUsernamePattern.hasMatch(value);

/// Converts capital letters to lowercase before the allowed-character filter
/// removes punctuation, whitespace, and symbols.
class XmoUsernameLowercaseFormatter extends TextInputFormatter {
  const XmoUsernameLowercaseFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    return newValue.copyWith(text: newValue.text.toLowerCase());
  }
}

List<TextInputFormatter> xmoUsernameInputFormatters() => [
  const XmoUsernameLowercaseFormatter(),
  FilteringTextInputFormatter.allow(_xmoUsernameAllowedCharacters),
];
