import 'dart:io';

import 'package:test/test.dart';
import 'package:xmo_auth_server/src/endpoint_modules.dart';

Future<void> _noop(HttpRequest _) async {}

void main() {
  const module = UserDirectoryEndpointModule(
    upsert: _noop,
    search: _noop,
    provisionSecureLogin: _noop,
  );

  test('matches secure sign-in provisioning route aliases', () {
    expect(
      module.handlesProvisionSecureLogin('/users/provision-secure-login'),
      isTrue,
    );
    expect(
      module.handlesProvisionSecureLogin(
        '/auth/users/provision-secure-login',
      ),
      isTrue,
    );
    expect(
      module.handlesProvisionSecureLogin(
        '/auth/otp/users/provision-secure-login',
      ),
      isTrue,
    );
    expect(module.handlesProvisionSecureLogin('/users/search'), isFalse);
  });
}
