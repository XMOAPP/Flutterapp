import 'package:flutter_test/flutter_test.dart';
import 'package:xmo/screens/channel/channel_admin_panel_screen.dart';
import 'package:xmo/screens/channel/channel_info_screen.dart';
import 'package:xmo/screens/direct_chat/user_profile_screen.dart';
import 'package:xmo/screens/group/admin_panel_screen.dart';
import 'package:xmo/screens/group/group_info_screen.dart';
import 'package:xmo/screens/matrix_chat_screen.dart';
import 'package:xmo/screens/moderation/moderator_reports_screen.dart';
import 'package:xmo/widgets/report_sheet.dart';

void main() {
  test('reporting entry points compile together', () {
    expect(MatrixChatScreen, isNotNull);
    expect(UserProfileScreen, isNotNull);
    expect(GroupInfoScreen, isNotNull);
    expect(ChannelInfoScreen, isNotNull);
    expect(AdminPanelScreen, isNotNull);
    expect(ChannelAdminPanelScreen, isNotNull);
    expect(ModeratorReportsScreen, isNotNull);
    expect(showXmoReportSheet, isA<Function>());
  });
}
