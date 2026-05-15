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

  static const requireEmailOtp = bool.fromEnvironment(
    'XMO_REQUIRE_EMAIL_OTP',
    defaultValue: true,
  );

  static const reownProjectId = String.fromEnvironment(
    'XMO_REOWN_PROJECT_ID',
    defaultValue: 'aeb4b4a85b194d2c749a857947220b2d',
  );
}
