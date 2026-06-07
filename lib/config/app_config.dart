class AppConfig {
  static const homeserverUrl = String.fromEnvironment(
    'XMO_HOMESERVER_URL',
    defaultValue: 'http://localhost:8008',
  );

  static const matrixServerName = String.fromEnvironment(
    'XMO_MATRIX_SERVER_NAME',
    defaultValue: 'localhost',
  );

  static const otpServerUrl = String.fromEnvironment(
    'XMO_OTP_SERVER_URL',
    defaultValue: 'https://xmo-matrix.centralindia.cloudapp.azure.com/auth/otp',
  );

  static const donationServerUrl = String.fromEnvironment(
    'XMO_DONATION_SERVER_URL',
    defaultValue: '',
  );

  static const requireEmailOtp = bool.fromEnvironment(
    'XMO_REQUIRE_EMAIL_OTP',
    defaultValue: true,
  );

  static const reownProjectId = String.fromEnvironment(
    'XMO_REOWN_PROJECT_ID',
    defaultValue: 'aeb4b4a85b194d2c749a857947220b2d',
  );

  static const thirdwebClientId = String.fromEnvironment(
    'XMO_THIRDWEB_CLIENT_ID',
    defaultValue: '81d97ee5ab262c8d202bc75ca83cc6f5',
  );

  static const donationRecipientAddress = String.fromEnvironment(
    'XMO_DONATION_RECIPIENT_ADDRESS',
    defaultValue: '0xc1a4BF16f64f5eE26b7C73831eF8bc70f200EacB',
  );

  static const pushGatewayUrl = String.fromEnvironment(
    'XMO_PUSH_GATEWAY_URL',
    defaultValue:
        'https://xmo-matrix.centralindia.cloudapp.azure.com/auth/otp/push',
  );

  static const pushAppId = String.fromEnvironment(
    'XMO_PUSH_APP_ID',
    defaultValue: 'com.xmo.xmo',
  );

  static const pushProfileTag = String.fromEnvironment(
    'XMO_PUSH_PROFILE_TAG',
    defaultValue: 'mobile',
  );
}
