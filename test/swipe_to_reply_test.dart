import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xmo/widgets/matrix_chat/swipe_to_reply.dart';

void main() {
  testWidgets('right swipe past threshold starts reply and snaps back', (
    tester,
  ) async {
    var replies = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SwipeToReply(
            onReply: () => replies++,
            child: const SizedBox(
              key: ValueKey('message'),
              width: 300,
              height: 80,
            ),
          ),
        ),
      ),
    );

    await tester.drag(find.byType(SwipeToReply), const Offset(70, 0));
    await tester.pumpAndSettle();

    expect(replies, 1);
    expect(
      tester.getTopLeft(find.byKey(const ValueKey('message'))).dx,
      closeTo(0, 0.1),
    );
  });

  testWidgets('short and left swipes do not start reply', (tester) async {
    var replies = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SwipeToReply(
            onReply: () => replies++,
            child: const SizedBox(
              key: ValueKey('message'),
              width: 300,
              height: 80,
            ),
          ),
        ),
      ),
    );

    await tester.drag(find.byType(SwipeToReply), const Offset(30, 0));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(SwipeToReply), const Offset(-70, 0));
    await tester.pumpAndSettle();

    expect(replies, 0);
  });

  testWidgets('null callback leaves child without a swipe gesture', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SwipeToReply(child: SizedBox(key: ValueKey('message'))),
        ),
      ),
    );

    expect(find.byType(GestureDetector), findsNothing);
  });
}
