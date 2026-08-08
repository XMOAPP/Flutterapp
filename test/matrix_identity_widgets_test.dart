import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';
import 'package:xmo/screens/user_profile_preview_screen.dart';
import 'package:xmo/screens/user_search/user_tile.dart';

void main() {
  const userId = '@hunter:xmo.example.com';

  testWidgets('user search tile hides a full-ID display name', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: UserTile(
            profile: Profile(userId: userId, displayName: userId),
            onTap: () {},
          ),
        ),
      ),
    );

    expect(find.text('Hunter'), findsOneWidget);
    expect(find.text('@hunter'), findsOneWidget);
    expect(find.text(userId), findsNothing);
  });

  testWidgets('profile preview hides a full-ID display name', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: UserProfilePreviewScreen(
          profile: Profile(userId: userId, displayName: userId),
        ),
      ),
    );

    expect(find.text('Hunter'), findsOneWidget);
    expect(find.text('@hunter'), findsOneWidget);
    expect(find.text(userId), findsNothing);
  });
}
