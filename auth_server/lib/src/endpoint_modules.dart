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

class WalletEndpointModule {
  const WalletEndpointModule({required this.nonce, required this.verify});

  final EndpointHandler nonce;
  final EndpointHandler verify;

  bool handlesNonce(String path) =>
      path == '/wallet/nonce' || path == '/auth/wallet/nonce';

  bool handlesVerify(String path) =>
      path == '/wallet/verify' || path == '/auth/wallet/verify';
}

class AzureBlobEndpointModule {
  const AzureBlobEndpointModule({required this.signUpload});

  final EndpointHandler signUpload;

  bool handlesSignUpload(String path) =>
      path == '/media/chunks/azure/sign-upload' ||
      path == '/auth/media/chunks/azure/sign-upload' ||
      path == '/auth/otp/media/chunks/azure/sign-upload';
}

class UserDirectoryEndpointModule {
  const UserDirectoryEndpointModule({
    required this.upsert,
    required this.search,
  });

  final EndpointHandler upsert;
  final EndpointHandler search;

  bool handlesUpsert(String path) =>
      path == '/users/upsert' ||
      path == '/auth/users/upsert' ||
      path == '/auth/otp/users/upsert';

  bool handlesSearch(String path) =>
      path == '/users/search' ||
      path == '/auth/users/search' ||
      path == '/auth/otp/users/search';
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
