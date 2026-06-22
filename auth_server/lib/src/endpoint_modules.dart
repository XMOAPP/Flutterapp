import 'dart:io';

typedef EndpointHandler = Future<void> Function(HttpRequest request);

/// Route modules keep endpoint ownership separate from the HTTP server loop.
/// Handler implementation remains injectable for unit tests.
class OtpEndpointModule {
  const OtpEndpointModule({required this.send, required this.verify});

  final EndpointHandler send;
  final EndpointHandler verify;

  bool handlesSend(String path) =>
      path == '/' || path == '/send' || path == '/auth/otp/send';
  bool handlesVerify(String path) =>
      path == '/verify' || path == '/auth/otp/verify';
}

class DonationEndpointModule {
  const DonationEndpointModule(this.create);
  final EndpointHandler create;

  bool handles(String path) =>
      path == '/donations/create' ||
      path == '/auth/donations/create' ||
      path == '/auth/otp/donations/create';
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
