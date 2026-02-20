import 'package:flutter_test/flutter_test.dart';
import 'package:xmo/main.dart';

void main() {
  testWidgets('XMO app smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const XmoApp());
    expect(find.text('xmo'), findsOneWidget);
  });
}
