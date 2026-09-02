import 'dart:io';

import 'package:test/test.dart';
import 'package:xmo_auth_server/src/endpoint_modules.dart';

Future<void> _noop(HttpRequest _) async {}

void main() {
  const module = UserDirectoryEndpointModule(
    upsert: _noop,
    search: _noop,
    checkUsernameAvailability: _noop,
    registerOidcAccount: _noop,
    prepareSecureRegistration: _noop,
    provisionSecureLogin: _noop,
    mfaStatus: _noop,
  );

  test('matches username availability route aliases', () {
    expect(
      module.handlesUsernameAvailability('/accounts/username-availability'),
      isTrue,
    );
    expect(
      module.handlesUsernameAvailability(
        '/auth/accounts/username-availability',
      ),
      isTrue,
    );
    expect(
      module.handlesUsernameAvailability(
        '/auth/otp/accounts/username-availability',
      ),
      isTrue,
    );
    expect(module.handlesUsernameAvailability('/accounts/register'), isFalse);
  });

  test('matches OIDC account registration route aliases', () {
    expect(module.handlesRegisterOidcAccount('/accounts/register'), isTrue);
    expect(
      module.handlesRegisterOidcAccount('/auth/accounts/register'),
      isTrue,
    );
    expect(
      module.handlesRegisterOidcAccount('/auth/otp/accounts/register'),
      isTrue,
    );
    expect(module.handlesRegisterOidcAccount('/users/search'), isFalse);
  });

  test('matches secure registration route aliases', () {
    expect(
      module.handlesPrepareSecureRegistration(
        '/users/prepare-secure-registration',
      ),
      isTrue,
    );
    expect(
      module.handlesPrepareSecureRegistration(
        '/auth/users/prepare-secure-registration',
      ),
      isTrue,
    );
    expect(
      module.handlesPrepareSecureRegistration(
        '/auth/otp/users/prepare-secure-registration',
      ),
      isTrue,
    );
    expect(module.handlesPrepareSecureRegistration('/users/search'), isFalse);
  });

  test('matches post-registration secure-login route aliases', () {
    expect(
      module.handlesProvisionSecureLogin('/users/provision-secure-login'),
      isTrue,
    );
    expect(
      module.handlesProvisionSecureLogin('/auth/users/provision-secure-login'),
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

  test('matches authenticated MFA status route aliases', () {
    expect(module.handlesMfaStatus('/security/mfa-status'), isTrue);
    expect(module.handlesMfaStatus('/auth/security/mfa-status'), isTrue);
    expect(module.handlesMfaStatus('/auth/otp/security/mfa-status'), isTrue);
    expect(module.handlesMfaStatus('/security/mfa-setup'), isFalse);
  });

  const recoveryModule = RecoveryEmailEndpointModule(
    prepareLocalEnrollment: _noop,
    completeLocalEnrollment: _noop,
    startChange: _noop,
    confirmChange: _noop,
  );

  test('does not expose the legacy public recovery email linking route', () {
    expect(
      recoveryModule.handlesPrepareLocalEnrollment('/password/link-email'),
      isFalse,
    );
    expect(
      recoveryModule.handlesPrepareLocalEnrollment(
        '/accounts/recovery-email/local-enrollment/prepare',
      ),
      isTrue,
    );
    expect(
      recoveryModule.handlesCompleteLocalEnrollment(
        '/accounts/recovery-email/local-enrollment/complete',
      ),
      isTrue,
    );
    expect(
      recoveryModule.handlesStartChange('/account/recovery-email/change/start'),
      isTrue,
    );
  });
}
