import 'dart:convert';
import 'dart:typed_data';

const String xmoContactContentKey = 'com.xmo.contact';

class XmoContactCard {
  static const int currentVersion = 1;

  final String displayName;
  final String phoneNumber;

  const XmoContactCard({
    required this.displayName,
    required this.phoneNumber,
  });

  factory XmoContactCard.create({
    required String displayName,
    required String phoneNumber,
  }) {
    final cleanName = _cleanValue(displayName, maxLength: 120);
    final cleanNumber = _cleanValue(phoneNumber, maxLength: 80);
    if (cleanName.isEmpty || cleanNumber.isEmpty) {
      throw const FormatException('Contact name and phone number are required');
    }
    return XmoContactCard(
      displayName: cleanName,
      phoneNumber: cleanNumber,
    );
  }

  static XmoContactCard? fromEventContent(Map<String, dynamic> content) {
    final raw = content[xmoContactContentKey];
    if (raw is! Map) return null;
    if (raw['version'] != currentVersion) return null;

    final name = raw['display_name'];
    final number = raw['phone_number'];
    if (name is! String || number is! String) return null;

    try {
      return XmoContactCard.create(
        displayName: name,
        phoneNumber: number,
      );
    } on FormatException {
      return null;
    }
  }

  Map<String, dynamic> toJson() => {
        'version': currentVersion,
        'display_name': displayName,
        'phone_number': phoneNumber,
      };

  String get fileName {
    final safeName = displayName
        .replaceAll(RegExp(r'[^A-Za-z0-9_-]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    return '${safeName.isEmpty ? 'contact' : safeName}.vcf';
  }

  Uint8List toVCardBytes() {
    final escapedName = _escapeVCard(displayName);
    final escapedNumber = _escapeVCard(phoneNumber);
    final vCard = <String>[
      'BEGIN:VCARD',
      'VERSION:3.0',
      'N:;$escapedName;;;',
      'FN:$escapedName',
      'TEL;TYPE=CELL:$escapedNumber',
      'END:VCARD',
      '',
    ].join('\r\n');
    return Uint8List.fromList(utf8.encode(vCard));
  }

  static String _cleanValue(String value, {required int maxLength}) {
    final clean = value.replaceAll(RegExp(r'[\r\n\u0000]'), ' ').trim();
    if (clean.length <= maxLength) return clean;
    return clean.substring(0, maxLength).trimRight();
  }

  static String _escapeVCard(String value) => value
      .replaceAll('\\', '\\\\')
      .replaceAll(';', r'\;')
      .replaceAll(',', r'\,')
      .replaceAll('\r', '')
      .replaceAll('\n', r'\n');
}
