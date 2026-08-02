import 'dart:convert';
import 'dart:typed_data';

const String xmoContactContentKey = 'com.xmo.contact';

class XmoContactCard {
  static const int currentVersion = 1;

  final String displayName;
  final String? phoneNumber;
  final String? username;
  final String? userId;

  const XmoContactCard({
    required this.displayName,
    this.phoneNumber,
    this.username,
    this.userId,
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

  factory XmoContactCard.createXmoUser({
    required String displayName,
    required String userId,
    String? username,
  }) {
    final cleanName = _cleanValue(displayName, maxLength: 120);
    final cleanUserId = _cleanValue(userId, maxLength: 160);
    final cleanUsername = _cleanUsername(
      username?.trim().isNotEmpty == true
          ? username!
          : _usernameFromUserId(cleanUserId),
    );
    if (cleanName.isEmpty || cleanUserId.isEmpty || cleanUsername == null) {
      throw const FormatException('XMO user name and ID are required');
    }
    return XmoContactCard(
      displayName: cleanName,
      username: cleanUsername,
      userId: cleanUserId,
    );
  }

  static XmoContactCard? fromEventContent(Map<String, dynamic> content) {
    final raw = content[xmoContactContentKey];
    if (raw is! Map) return null;
    if (raw['version'] != currentVersion) return null;

    final name = raw['display_name'];
    final number = raw['phone_number'];
    final username = raw['username'];
    final userId = raw['user_id'];
    if (name is! String) return null;

    try {
      if (userId is String) {
        return XmoContactCard.createXmoUser(
          displayName: name,
          userId: userId,
          username: username is String ? username : null,
        );
      }
      if (number is String) {
        return XmoContactCard.create(
          displayName: name,
          phoneNumber: number,
        );
      }
      return null;
    } on FormatException {
      return null;
    }
  }

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{
      'version': currentVersion,
      'display_name': displayName,
    };
    final cleanPhone = phoneNumber;
    if (cleanPhone != null && cleanPhone.isNotEmpty) {
      json['phone_number'] = cleanPhone;
    }
    final cleanUsername = username;
    if (cleanUsername != null && cleanUsername.isNotEmpty) {
      json['username'] = cleanUsername;
    }
    final cleanUserId = userId;
    if (cleanUserId != null && cleanUserId.isNotEmpty) {
      json['user_id'] = cleanUserId;
    }
    return json;
  }

  String get subtitle {
    final cleanUsername = username;
    if (cleanUsername != null && cleanUsername.isNotEmpty) {
      return cleanUsername;
    }
    return phoneNumber ?? '';
  }

  String get fileName {
    final safeName = displayName
        .replaceAll(RegExp(r'[^A-Za-z0-9_-]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    return '${safeName.isEmpty ? 'contact' : safeName}.vcf';
  }

  Uint8List toVCardBytes() {
    final escapedName = _escapeVCard(displayName);
    final cleanPhone = phoneNumber;
    final cleanUsername = username;
    final cleanUserId = userId;
    final vCard = <String>[
      'BEGIN:VCARD',
      'VERSION:3.0',
      'N:;$escapedName;;;',
      'FN:$escapedName',
      if (cleanPhone != null && cleanPhone.isNotEmpty)
        'TEL;TYPE=CELL:${_escapeVCard(cleanPhone)}',
      if (cleanUsername != null && cleanUsername.isNotEmpty)
        'IMPP:xmo:${_escapeVCard(cleanUsername)}',
      if (cleanUserId != null && cleanUserId.isNotEmpty)
        'X-XMO-USERID:${_escapeVCard(cleanUserId)}',
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

  static String? _cleanUsername(String value) {
    final clean = _cleanValue(value, maxLength: 80);
    if (clean.isEmpty) return null;
    final withoutAt = clean.startsWith('@') ? clean.substring(1) : clean;
    final localpart = withoutAt.split(':').first.trim();
    if (localpart.isEmpty) return null;
    return '@$localpart';
  }

  static String _usernameFromUserId(String userId) {
    final clean = _cleanValue(userId, maxLength: 160);
    final withoutAt = clean.startsWith('@') ? clean.substring(1) : clean;
    return '@${withoutAt.split(':').first}';
  }
}
