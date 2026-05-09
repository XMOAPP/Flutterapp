class XmoInviteLink {
  final String linkId;
  final String url;
  final String roomId;
  final DateTime createdAt;
  final DateTime? expiresAt;
  final int usedCount;
  final String createdBy;
  final bool isActive;

  const XmoInviteLink({
    required this.linkId,
    required this.url,
    required this.roomId,
    required this.createdAt,
    this.expiresAt,
    this.usedCount = 0,
    required this.createdBy,
    this.isActive = true,
  });

  bool get isExpired => expiresAt != null && DateTime.now().isAfter(expiresAt!);

  bool get canBeUsed => isActive && !isExpired;

  XmoInviteLink copyWith({
    String? linkId,
    String? url,
    String? roomId,
    DateTime? createdAt,
    DateTime? expiresAt,
    int? usedCount,
    String? createdBy,
    bool? isActive,
  }) {
    return XmoInviteLink(
      linkId: linkId ?? this.linkId,
      url: url ?? this.url,
      roomId: roomId ?? this.roomId,
      createdAt: createdAt ?? this.createdAt,
      expiresAt: expiresAt ?? this.expiresAt,
      usedCount: usedCount ?? this.usedCount,
      createdBy: createdBy ?? this.createdBy,
      isActive: isActive ?? this.isActive,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'link_id': linkId,
      'url': url,
      'room_id': roomId,
      'created_at': createdAt.toIso8601String(),
      if (expiresAt != null) 'expires_at': expiresAt!.toIso8601String(),
      'used_count': usedCount,
      'created_by': createdBy,
      'is_active': isActive,
    };
  }

  factory XmoInviteLink.fromJson(Map<dynamic, dynamic> json) {
    return XmoInviteLink(
      linkId: json['link_id'] as String? ?? '',
      url: json['url'] as String? ?? '',
      roomId: json['room_id'] as String? ?? '',
      createdAt: DateTime.tryParse(json['created_at'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      expiresAt: DateTime.tryParse(json['expires_at'] as String? ?? ''),
      usedCount: (json['used_count'] as num?)?.toInt() ?? 0,
      createdBy: json['created_by'] as String? ?? '',
      isActive: json['is_active'] as bool? ?? true,
    );
  }
}
