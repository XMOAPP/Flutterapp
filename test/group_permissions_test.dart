import 'package:flutter_test/flutter_test.dart';
import 'package:xmo/models/group_models.dart';
import 'package:xmo/services/group_service.dart';

void main() {
  group('group role mapping', () {
    test('maps power levels to visible roles', () {
      expect(GroupMember.roleFromPowerLevel(100), MemberRole.owner);
      expect(GroupMember.roleFromPowerLevel(75), MemberRole.admin);
      expect(GroupMember.roleFromPowerLevel(50), MemberRole.moderator);
      expect(GroupMember.roleFromPowerLevel(25), MemberRole.member);
      expect(GroupMember.roleFromPowerLevel(0), MemberRole.member);
      expect(GroupMember.roleFromPowerLevel(-1), MemberRole.restricted);
    });
  });

  group('group permission gates', () {
    test('matches XMO role thresholds', () {
      expect(GroupService.canInviteMembers(49), isFalse);
      expect(GroupService.canInviteMembers(50), isTrue);
      expect(GroupService.canPinMessages(49), isFalse);
      expect(GroupService.canPinMessages(50), isTrue);
      expect(GroupService.canModerateMembers(49), isFalse);
      expect(GroupService.canModerateMembers(50), isTrue);
      expect(GroupService.canEditSettings(74), isFalse);
      expect(GroupService.canEditSettings(75), isTrue);
      expect(GroupService.canManageAdmins(99), isFalse);
      expect(GroupService.canManageAdmins(100), isTrue);
    });

    test('moderators can only act on lower-ranked members', () {
      expect(
        GroupService.canActOnMember(actorPowerLevel: 50, targetPowerLevel: 0),
        isTrue,
      );
      expect(
        GroupService.canActOnMember(actorPowerLevel: 50, targetPowerLevel: 50),
        isFalse,
      );
      expect(
        GroupService.canActOnMember(
          actorPowerLevel: 100,
          targetPowerLevel: 100,
        ),
        isFalse,
      );
    });

    test('only owners can change lower-ranked admin roles', () {
      expect(
        GroupService.canChangePowerLevel(
          actorPowerLevel: 75,
          targetPowerLevel: 0,
          newPowerLevel: 50,
        ),
        isFalse,
      );
      expect(
        GroupService.canChangePowerLevel(
          actorPowerLevel: 100,
          targetPowerLevel: 0,
          newPowerLevel: 75,
        ),
        isTrue,
      );
      expect(
        GroupService.canChangePowerLevel(
          actorPowerLevel: 100,
          targetPowerLevel: 100,
          newPowerLevel: 0,
        ),
        isFalse,
      );
      expect(
        GroupService.canChangePowerLevel(
          actorPowerLevel: 100,
          targetPowerLevel: 0,
          newPowerLevel: 100,
        ),
        isFalse,
      );
    });
  });

  group('admin action log model', () {
    test('serializes and deserializes admin actions', () {
      final timestamp = DateTime.utc(2026, 5, 6, 12, 15);
      final action = AdminAction(
        actionId: 'action-1',
        type: AdminActionType.memberPromoted,
        performedBy: '@owner:localhost',
        targetUser: '@alice:localhost',
        timestamp: timestamp,
        metadata: const {'power_level': 75},
      );

      final decoded = AdminAction.fromJson(action.toJson());

      expect(decoded.actionId, 'action-1');
      expect(decoded.type, AdminActionType.memberPromoted);
      expect(decoded.label, 'Promoted member');
      expect(decoded.performedBy, '@owner:localhost');
      expect(decoded.targetUser, '@alice:localhost');
      expect(decoded.timestamp, timestamp);
      expect(decoded.metadata['power_level'], 75);
    });
  });

  group('member restriction model', () {
    test('serializes read-only restrictions', () {
      final restrictedAt = DateTime.utc(2030, 5, 6, 13, 30);
      final expiresAt = DateTime.utc(2030, 5, 7, 13, 30);
      final restriction = MemberRestriction(
        userId: '@alice:localhost',
        type: RestrictionType.readOnly,
        expiresAt: expiresAt,
        reason: 'cooldown',
        restrictedBy: '@owner:localhost',
        restrictedAt: restrictedAt,
      );

      final decoded = MemberRestriction.fromJson(restriction.toJson());

      expect(decoded.userId, '@alice:localhost');
      expect(decoded.type, RestrictionType.readOnly);
      expect(decoded.expiresAt, expiresAt);
      expect(decoded.reason, 'cooldown');
      expect(decoded.restrictedBy, '@owner:localhost');
      expect(decoded.restrictedAt, restrictedAt);
      expect(decoded.isExpired, isFalse);
    });
  });
}
