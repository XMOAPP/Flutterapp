import 'dart:io';

typedef EndpointHandler = Future<void> Function(HttpRequest request);

/// Route modules keep endpoint ownership separate from the HTTP server loop.
/// Handler implementation remains injectable for unit tests.
class OtpEndpointModule {
  const OtpEndpointModule({required this.send, required this.verify});

  final EndpointHandler send;
  final EndpointHandler verify;

  bool handlesSend(String path) =>
      path == '/' ||
      path == '/send' ||
      path == '/auth/otp/send' ||
      path == '/auth/send-otp' ||
      path == '/auth/resend-otp';
  bool handlesVerify(String path) =>
      path == '/verify' || path == '/auth/otp/verify';
}

class PasswordResetEndpointModule {
  const PasswordResetEndpointModule({
    required this.linkEmail,
    required this.start,
    required this.complete,
  });

  final EndpointHandler linkEmail;
  final EndpointHandler start;
  final EndpointHandler complete;

  bool handlesLinkEmail(String path) =>
      path == '/password/link-email' ||
      path == '/auth/otp/password/link-email' ||
      path == '/auth/password/link-email';

  bool handlesStart(String path) =>
      path == '/password/reset/start' ||
      path == '/auth/otp/password/reset/start' ||
      path == '/auth/password/reset/start' ||
      path == '/auth/forgot-password';

  bool handlesComplete(String path) =>
      path == '/password/reset/complete' ||
      path == '/auth/otp/password/reset/complete' ||
      path == '/auth/password/reset/complete';
}

class DonationEndpointModule {
  const DonationEndpointModule(this.create);
  final EndpointHandler create;

  bool handles(String path) =>
      path == '/donations/create' ||
      path == '/auth/donations/create' ||
      path == '/auth/otp/donations/create';
}

class InviteEndpointModule {
  const InviteEndpointModule({
    required this.create,
    required this.list,
    required this.revoke,
    required this.preview,
    required this.avatar,
    required this.redeem,
  });

  final EndpointHandler create;
  final EndpointHandler list;
  final EndpointHandler revoke;
  final EndpointHandler preview;
  final EndpointHandler avatar;
  final EndpointHandler redeem;

  bool handlesCreate(String path) => _matches(path, '/invites/create');
  bool handlesList(String path) => _matches(path, '/invites/list');
  bool handlesRevoke(String path) => _matches(path, '/invites/revoke');
  bool handlesPreview(String path) =>
      _tokenFromPath(path, suffix: '/preview') != null;
  bool handlesAvatar(String path) =>
      _tokenFromPath(path, suffix: '/avatar') != null;
  bool handlesRedeem(String path) =>
      _tokenFromPath(path, suffix: '/redeem') != null;

  static bool _matches(String path, String endpoint) =>
      path == endpoint ||
      path == '/auth$endpoint' ||
      path == '/auth/otp$endpoint';

  static String? tokenFromPreviewPath(String path) =>
      _tokenFromPath(path, suffix: '/preview');
  static String? tokenFromAvatarPath(String path) =>
      _tokenFromPath(path, suffix: '/avatar');
  static String? tokenFromRedeemPath(String path) =>
      _tokenFromPath(path, suffix: '/redeem');

  static String? _tokenFromPath(String path, {required String suffix}) {
    for (final prefix in const [
      '/invites/',
      '/auth/invites/',
      '/auth/otp/invites/'
    ]) {
      if (!path.startsWith(prefix) || !path.endsWith(suffix)) continue;
      final token = path.substring(prefix.length, path.length - suffix.length);
      if (RegExp(r'^[A-Za-z0-9_-]{40,64}$').hasMatch(token)) return token;
    }
    return null;
  }
}

class WalletEndpointModule {
  const WalletEndpointModule({
    required this.account,
    required this.usernameAvailability,
    required this.nonce,
    required this.verify,
  });

  final EndpointHandler account;
  final EndpointHandler usernameAvailability;
  final EndpointHandler nonce;
  final EndpointHandler verify;

  bool handlesAccount(String path) =>
      path == '/wallet/account' || path == '/auth/wallet/account';

  bool handlesUsernameAvailability(String path) =>
      path == '/wallet/username-availability' ||
      path == '/auth/wallet/username-availability';

  bool handlesNonce(String path) =>
      path == '/wallet/nonce' || path == '/auth/wallet/nonce';

  bool handlesVerify(String path) =>
      path == '/wallet/verify' || path == '/auth/wallet/verify';
}

class AzureBlobEndpointModule {
  const AzureBlobEndpointModule({
    required this.signUpload,
    required this.download,
  });

  final EndpointHandler signUpload;
  final EndpointHandler download;

  bool handlesSignUpload(String path) =>
      path == '/media/chunks/azure/sign-upload' ||
      path == '/auth/media/chunks/azure/sign-upload' ||
      path == '/auth/otp/media/chunks/azure/sign-upload';

  bool handlesDownload(String path) =>
      path == '/media/chunks/azure/download' ||
      path == '/auth/media/chunks/azure/download' ||
      path == '/auth/otp/media/chunks/azure/download';
}

class UserDirectoryEndpointModule {
  const UserDirectoryEndpointModule({
    required this.upsert,
    required this.search,
    required this.checkUsernameAvailability,
    required this.registerOidcAccount,
    required this.prepareSecureRegistration,
    required this.provisionSecureLogin,
  });

  final EndpointHandler upsert;
  final EndpointHandler search;
  final EndpointHandler checkUsernameAvailability;
  final EndpointHandler registerOidcAccount;
  final EndpointHandler prepareSecureRegistration;
  final EndpointHandler provisionSecureLogin;

  bool handlesUpsert(String path) =>
      path == '/users/upsert' ||
      path == '/auth/users/upsert' ||
      path == '/auth/otp/users/upsert';

  bool handlesSearch(String path) =>
      path == '/users/search' ||
      path == '/auth/users/search' ||
      path == '/auth/otp/users/search';

  bool handlesUsernameAvailability(String path) =>
      path == '/accounts/username-availability' ||
      path == '/auth/accounts/username-availability' ||
      path == '/auth/otp/accounts/username-availability';

  bool handlesRegisterOidcAccount(String path) =>
      path == '/accounts/register' ||
      path == '/auth/accounts/register' ||
      path == '/auth/otp/accounts/register';

  bool handlesPrepareSecureRegistration(String path) =>
      path == '/users/prepare-secure-registration' ||
      path == '/auth/users/prepare-secure-registration' ||
      path == '/auth/otp/users/prepare-secure-registration';

  bool handlesProvisionSecureLogin(String path) =>
      path == '/users/provision-secure-login' ||
      path == '/auth/users/provision-secure-login' ||
      path == '/auth/otp/users/provision-secure-login';
}

class ReportEndpointModule {
  const ReportEndpointModule({
    required this.submit,
    required this.list,
    required this.update,
  });

  final EndpointHandler submit;
  final EndpointHandler list;
  final EndpointHandler update;

  bool handlesSubmit(String path) =>
      path == '/reports/submit' ||
      path == '/auth/reports/submit' ||
      path == '/auth/otp/reports/submit';

  bool handlesList(String path) =>
      path == '/reports/review/list' ||
      path == '/auth/reports/review/list' ||
      path == '/auth/otp/reports/review/list';

  bool handlesUpdate(String path) =>
      path == '/reports/review/update' ||
      path == '/auth/reports/review/update' ||
      path == '/auth/otp/reports/review/update';
}

class AccountDeletionEndpointModule {
  const AccountDeletionEndpointModule({
    required this.deleteData,
    required this.requestExternal,
    required this.confirmExternal,
  });

  final EndpointHandler deleteData;
  final EndpointHandler requestExternal;
  final EndpointHandler confirmExternal;

  bool handlesDeleteData(String path) =>
      path == '/account/delete-data' ||
      path == '/auth/account/delete-data' ||
      path == '/auth/otp/account/delete-data';

  bool handlesExternalRequest(String path) =>
      path == '/account-deletion/request';

  bool handlesExternalConfirm(String path) =>
      path == '/account-deletion/confirm';
}

class ChannelAnalyticsEndpointModule {
  const ChannelAnalyticsEndpointModule({
    required this.view,
    required this.forward,
    required this.stats,
  });

  final EndpointHandler view;
  final EndpointHandler forward;
  final EndpointHandler stats;

  bool handlesView(String path) =>
      path == '/channel/analytics/view' ||
      path == '/auth/channel/analytics/view' ||
      path == '/auth/otp/channel/analytics/view';
  bool handlesForward(String path) =>
      path == '/channel/analytics/forward' ||
      path == '/auth/channel/analytics/forward' ||
      path == '/auth/otp/channel/analytics/forward';
  bool handlesStats(String path) =>
      path == '/channel/analytics/stats' ||
      path == '/auth/channel/analytics/stats' ||
      path == '/auth/otp/channel/analytics/stats';
}

class PushGatewayEndpointModule {
  const PushGatewayEndpointModule(this.forward);
  final EndpointHandler forward;

  bool handles(String path) =>
      path == '/push' ||
      path == '/auth/otp/push' ||
      path == '/_matrix/push/v1/notify' ||
      path == '/auth/push/_matrix/push/v1/notify' ||
      path == '/auth/otp/_matrix/push/v1/notify';
}
