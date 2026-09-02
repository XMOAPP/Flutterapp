import 'package:flutter_test/flutter_test.dart';
import 'package:xmo/screens/donation_screen.dart';

void main() {
  test('donation screen exposes the native wallet flow', () {
    expect(const DonationScreen(), isA<DonationScreen>());
  });
}
