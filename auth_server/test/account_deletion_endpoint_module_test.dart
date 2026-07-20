import 'dart:io';

import 'package:test/test.dart';
import 'package:xmo_auth_server/src/endpoint_modules.dart';

Future<void> _noop(HttpRequest _) async {}

void main() {
  const module = AccountDeletionEndpointModule(
    deleteData: _noop,
    requestExternal: _noop,
    confirmExternal: _noop,
  );

  test('matches authenticated account data deletion routes', () {
    expect(module.handlesDeleteData('/account/delete-data'), isTrue);
    expect(module.handlesDeleteData('/auth/account/delete-data'), isTrue);
    expect(module.handlesDeleteData('/auth/otp/account/delete-data'), isTrue);
    expect(module.handlesDeleteData('/account-deletion'), isFalse);
  });

  test('matches external account deletion routes', () {
    expect(
      module.handlesExternalRequest('/account-deletion/request'),
      isTrue,
    );
    expect(
      module.handlesExternalConfirm('/account-deletion/confirm'),
      isTrue,
    );
    expect(module.handlesExternalRequest('/account-deletion/confirm'), isFalse);
  });
}
