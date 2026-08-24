import 'package:test/test.dart';
import 'package:xmo_auth_server/src/health_status.dart';

void main() {
  test('public health output does not disclose deployment configuration', () {
    expect(buildHealthStatus(), {'ok': true});
  });
}
