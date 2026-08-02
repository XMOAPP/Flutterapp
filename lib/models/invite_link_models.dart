class XmoInviteLink {
  final String linkId;
  final String url;
  final String roomId;
  final String? roomName;
  final String? roomType;
  final DateTime createdAt;
  final DateTime? expiresAt;
  final int usedCount;
  final int? maxUses;
  final String createdBy;
  final bool isActive;

  const XmoInviteLink({
    required this.linkId,
    required this.url,
    this.roomId = '',
    this.roomName,
    this.roomType,
    required this.createdAt,
    this.expiresAt,
    this.usedCount = 0,
    this.maxUses,
    this.createdBy = '',
    this.isActive = true,
  });

  bool get isExpired => expiresAt != null && DateTime.now().isAfter(expiresAt!);
  bool get canBeUsed =>
      isActive && !isExpired && (maxUses == null || usedCount < maxUses!);

  XmoInviteLink copyWith({
    String? linkId,
    String? url,
    String? roomId,
    String? roomName,
    String? roomType,
    DateTime? createdAt,
    DateTime? expiresAt,
    int? usedCount,
    int? maxUses,
    String? createdBy,
    bool? isActive,
  }) =>
      XmoInviteLink(
        linkId: linkId ?? this.linkId,
        url: url ?? this.url,
        roomId: roomId ?? this.roomId,
        roomName: roomName ?? this.roomName,
        roomType: roomType ?? this.roomType,
        createdAt: createdAt ?? this.createdAt,
        expiresAt: expiresAt ?? this.expiresAt,
        usedCount: usedCount ?? this.usedCount,
        maxUses: maxUses ?? this.maxUses,
        createdBy: createdBy ?? this.createdBy,
        isActive: isActive ?? this.isActive,
      );

  Map<String, dynamic> toJson() => {
        'link_id': linkId,
        'url': url,
        'room_id': roomId,
        'created_at': createdAt.toIso8601String(),
        if (expiresAt != null) 'expires_at': expiresAt!.toIso8601String(),
        'used_count': usedCount,
        'created_by': createdBy,
        'is_active': isActive,
      };

  factory XmoInviteLink.fromJson(Map<dynamic, dynamic> json) => XmoInviteLink(
        linkId: _string(json, 'linkId', 'link_id'),
        url: _string(json, 'url'),
        roomId: _string(json, 'roomId', 'room_id'),
        roomName: _nullableString(json, 'name', 'roomName'),
        roomType: _nullableString(json, 'type', 'roomType'),
        createdAt: _date(json, 'createdAt', 'created_at') ??
            DateTime.fromMillisecondsSinceEpoch(0),
        expiresAt: _date(json, 'expiresAt', 'expires_at'),
        usedCount: _int(json, 'usedCount', 'used_count') ?? 0,
        maxUses: _int(json, 'maxUses', 'max_uses'),
        createdBy: _string(json, 'createdBy', 'created_by'),
        isActive: _bool(json, 'active', 'is_active') ?? true,
      );
}

class XmoInvitePreview {
  const XmoInvitePreview({
    required this.name,
    required this.type,
    required this.memberCount,
    required this.joinMode,
    required this.expiresAt,
    this.avatarUrl,
    this.topic,
  });

  final String name;
  final String type;
  final String? avatarUrl;
  final String? topic;
  final int memberCount;
  final String joinMode;
  final DateTime expiresAt;

  bool get requiresApproval => joinMode == 'knock';

  factory XmoInvitePreview.fromJson(Map<dynamic, dynamic> json) {
    final expiresAt = _date(json, 'expiresAt');
    if (expiresAt == null) throw const FormatException('Missing invite expiry');
    final type = _string(json, 'type');
    final joinMode = _string(json, 'joinMode');
    if (!const {'group', 'channel'}.contains(type) ||
        !const {'join', 'knock'}.contains(joinMode)) {
      throw const FormatException('Invalid invite metadata');
    }
    return XmoInvitePreview(
      name: _string(json, 'name'),
      type: type,
      avatarUrl: _nullableString(json, 'avatarUrl'),
      topic: _nullableString(json, 'topic'),
      memberCount: _int(json, 'memberCount') ?? 0,
      joinMode: joinMode,
      expiresAt: expiresAt,
    );
  }
}

class XmoInviteRedemption {
  const XmoInviteRedemption({required this.roomId, required this.action});
  final String roomId;
  final String action;

  factory XmoInviteRedemption.fromJson(Map<dynamic, dynamic> json) {
    final roomId = _string(json, 'roomId');
    final action = _string(json, 'action');
    if (!roomId.startsWith('!') || !const {'join', 'knock'}.contains(action)) {
      throw const FormatException('Invalid invite redemption');
    }
    return XmoInviteRedemption(roomId: roomId, action: action);
  }
}

String _string(Map<dynamic, dynamic> json, String key, [String? fallback]) =>
    (json[key] ?? (fallback == null ? null : json[fallback]))?.toString() ?? '';
String? _nullableString(
  Map<dynamic, dynamic> json,
  String key, [
  String? fallback,
]) {
  final value = _string(json, key, fallback).trim();
  return value.isEmpty ? null : value;
}

DateTime? _date(Map<dynamic, dynamic> json, String key, [String? fallback]) =>
    DateTime.tryParse(_string(json, key, fallback));
int? _int(Map<dynamic, dynamic> json, String key, [String? fallback]) {
  final value = json[key] ?? (fallback == null ? null : json[fallback]);
  return value is num ? value.toInt() : int.tryParse('$value');
}

bool? _bool(Map<dynamic, dynamic> json, String key, [String? fallback]) {
  final value = json[key] ?? (fallback == null ? null : json[fallback]);
  return value is bool ? value : null;
}
