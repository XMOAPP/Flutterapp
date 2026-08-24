import 'dart:io';

import 'package:test/test.dart';
import 'package:xmo_auth_server/src/endpoint_modules.dart';

Future<void> _noop(HttpRequest _) async {}

const _otp = OtpEndpointModule(send: _noop, verify: _noop);
const _passwordReset = PasswordResetEndpointModule(
  start: _noop,
  complete: _noop,
);
const _recoveryEmail = RecoveryEmailEndpointModule(
  prepareLocalEnrollment: _noop,
  completeLocalEnrollment: _noop,
  startChange: _noop,
  confirmChange: _noop,
);
const _invite = InviteEndpointModule(
  create: _noop,
  list: _noop,
  revoke: _noop,
  preview: _noop,
  avatar: _noop,
  redeem: _noop,
);
const _wallet = WalletEndpointModule(
  account: _noop,
  session: _noop,
  usernameAvailability: _noop,
  nonce: _noop,
  verify: _noop,
);
const _azureBlob = AzureBlobEndpointModule(signUpload: _noop, download: _noop);
const _userDirectory = UserDirectoryEndpointModule(
  upsert: _noop,
  search: _noop,
  checkUsernameAvailability: _noop,
  registerOidcAccount: _noop,
  prepareSecureRegistration: _noop,
  provisionSecureLogin: _noop,
);
const _reports = ReportEndpointModule(
  submit: _noop,
  list: _noop,
  update: _noop,
);
const _accountDeletion = AccountDeletionEndpointModule(
  deleteData: _noop,
  requestExternal: _noop,
  confirmExternal: _noop,
);
const _channelAnalytics = ChannelAnalyticsEndpointModule(
  view: _noop,
  forward: _noop,
  stats: _noop,
);
const _registry = EndpointAuthorizationRegistry(
  otp: _otp,
  passwordReset: _passwordReset,
  recoveryEmail: _recoveryEmail,
  donation: DonationEndpointModule(_noop),
  invite: _invite,
  wallet: _wallet,
  azureBlob: _azureBlob,
  userDirectory: _userDirectory,
  reports: _reports,
  accountDeletion: _accountDeletion,
  channelAnalytics: _channelAnalytics,
  push: PushGatewayEndpointModule(_noop),
);

void main() {
  EndpointAuthorizationPolicy? policy(String method, String path) =>
      _registry.policyFor(method: method, path: path);

  test('requires a Matrix user for every user-owned endpoint family', () {
    for (final path in [
      '/auth/account/delete-data',
      '/donations/create',
      '/auth/donations/create',
      '/auth/otp/donations/create',
      '/auth/invites/create',
      '/auth/otp/invites/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/redeem',
      '/auth/channel/analytics/view',
      '/auth/account/recovery-email/change/start',
      '/auth/media/chunks/azure/sign-upload',
      '/auth/users/upsert',
      '/auth/users/provision-secure-login',
      '/auth/reports/submit',
    ]) {
      expect(policy('POST', path), EndpointAuthorizationPolicy.matrixUser);
    }
    expect(
      policy('GET', '/auth/wallet/session'),
      EndpointAuthorizationPolicy.matrixUser,
    );
    expect(
      policy('GET', '/auth/media/chunks/azure/download'),
      EndpointAuthorizationPolicy.matrixUser,
    );
  });

  test('keeps email-proof and enrollment flows intentionally sessionless', () {
    for (final path in [
      '/auth/otp/send',
      '/auth/password/reset/start',
      '/account-deletion/confirm',
      '/auth/accounts/recovery-email/local-enrollment/prepare',
      '/auth/accounts/register',
      '/auth/users/prepare-secure-registration',
    ]) {
      expect(policy('POST', path), EndpointAuthorizationPolicy.proofBased);
    }
  });

  test(
    'classifies public, capability, and internal-service routes explicitly',
    () {
      const token = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
      expect(policy('GET', '/health'), EndpointAuthorizationPolicy.public);
      expect(
        policy('POST', '/auth/wallet/nonce'),
        EndpointAuthorizationPolicy.public,
      );
      expect(
        policy('GET', '/auth/invites/$token/preview'),
        EndpointAuthorizationPolicy.capability,
      );
      expect(
        policy('GET', '/auth/invites/$token/avatar'),
        EndpointAuthorizationPolicy.capability,
      );
      expect(
        policy('POST', '/_matrix/push/v1/notify'),
        EndpointAuthorizationPolicy.internalService,
      );
    },
  );

  test('rejects unknown paths and incorrect methods before dispatch', () {
    expect(policy('POST', '/password/link-email'), isNull);
    expect(policy('GET', '/auth/reports/submit'), isNull);
    expect(policy('POST', '/does-not-exist'), isNull);
  });
}
