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
