class AppConfig {
  static const homeserverUrl = String.fromEnvironment(
    'XMO_HOMESERVER_URL',
    defaultValue: 'https://xmo-matrix.centralindia.cloudapp.azure.com',
  );

  static const matrixServerName = String.fromEnvironment(
    'XMO_MATRIX_SERVER_NAME',
    defaultValue: 'xmo-matrix.centralindia.cloudapp.azure.com',
  );

  static const otpServerUrl = String.fromEnvironment(
    'XMO_OTP_SERVER_URL',
    defaultValue: 'https://xmo-matrix.centralindia.cloudapp.azure.com/auth/otp',
  );

  static const userDirectoryServerUrl = String.fromEnvironment(
    'XMO_USER_DIRECTORY_SERVER_URL',
    defaultValue: 'https://xmo-matrix.centralindia.cloudapp.azure.com/auth/otp',
  );

  static const reportServerUrl = String.fromEnvironment(
    'XMO_REPORT_SERVER_URL',
    defaultValue: 'https://xmo-matrix.centralindia.cloudapp.azure.com/auth/otp',
  );

  static const accountDeletionServerUrl = String.fromEnvironment(
    'XMO_ACCOUNT_DELETION_SERVER_URL',
    defaultValue: 'https://xmo-matrix.centralindia.cloudapp.azure.com/auth/otp',
  );

  static const channelAnalyticsServerUrl = String.fromEnvironment(
    'XMO_CHANNEL_ANALYTICS_SERVER_URL',
    defaultValue: 'https://xmo-matrix.centralindia.cloudapp.azure.com/auth/otp',
  );

  static const inviteServerUrl = String.fromEnvironment(
    'XMO_INVITE_SERVER_URL',
    defaultValue: 'https://xmo-matrix.centralindia.cloudapp.azure.com/auth/otp',
  );

  static const inviteWebBaseUrl = String.fromEnvironment(
    'XMO_INVITE_WEB_BASE_URL',
    defaultValue: 'https://xmo.dpdns.org',
  );

  static const accountDeletionWebUrl = String.fromEnvironment(
    'XMO_ACCOUNT_DELETION_WEB_URL',
    defaultValue: 'https://xmo.dpdns.org/account-deletion',
  );

  static const publicWebsiteUrl = String.fromEnvironment(
    'XMO_PUBLIC_WEBSITE_URL',
    defaultValue: 'https://xmo.dpdns.org/',
  );

  static const secureAccountUrl = String.fromEnvironment(
    'XMO_SECURE_ACCOUNT_URL',
    defaultValue: 'https://auth.xmo.dpdns.org/if/user/',
  );

  static const mfaSetupUrl = String.fromEnvironment(
    'XMO_MFA_SETUP_URL',
    defaultValue: 'https://auth.xmo.dpdns.org/if/flow/xmo-totp-setup/',
  );

  static const secureAccountRecoveryUrl = String.fromEnvironment(
    'XMO_SECURE_ACCOUNT_RECOVERY_URL',
    defaultValue: 'https://auth.xmo.dpdns.org/if/flow/default-recovery-flow/',
  );

  static const walletAuthServerUrl = String.fromEnvironment(
    'XMO_WALLET_AUTH_SERVER_URL',
    defaultValue:
        'https://xmo-matrix.centralindia.cloudapp.azure.com/auth/wallet',
  );

  static const donationServerUrl = String.fromEnvironment(
    'XMO_DONATION_SERVER_URL',
    defaultValue: '',
  );

  static const requireEmailOtp = bool.fromEnvironment(
    'XMO_REQUIRE_EMAIL_OTP',
    defaultValue: true,
  );

  static const enableLegacyPhonePasswordAuth = bool.fromEnvironment(
    'XMO_ENABLE_LEGACY_PHONE_PASSWORD_AUTH',
    defaultValue: false,
  );

  /// Enables the browser-based Matrix SSO flow during the OIDC migration.
  /// Keep this disabled until Synapse has an OIDC provider configured.
  static const enableSsoLogin = bool.fromEnvironment(
    'XMO_ENABLE_SSO_LOGIN',
    defaultValue: false,
  );

  /// Makes Authentik the credential authority and prevents the app from
  /// submitting passwords directly to Synapse. Enable only after the backend
  /// registration transaction and Synapse OIDC provider are deployed.
  static const oidcOnlyAuthentication = bool.fromEnvironment(
    'XMO_OIDC_ONLY_AUTHENTICATION',
    defaultValue: false,
  );

  /// The Synapse OIDC provider identifier, for example `authentik`.
  static const ssoIdpId = String.fromEnvironment(
    'XMO_SSO_IDP_ID',
    defaultValue: '',
  );

  /// Verified Android App Link used to return the one-time Matrix login token.
  static const ssoCallbackUrl = String.fromEnvironment(
    'XMO_SSO_CALLBACK_URL',
    defaultValue: 'https://xmo.dpdns.org/auth/callback',
  );

  /// Verified Android App Link used after an account deletion completes in the
  /// public web page. It is deliberately separate from the OIDC callback so a
  /// deletion notification can never be treated as a login response.
  static const accountDeletionCompletionUrl = String.fromEnvironment(
    'XMO_ACCOUNT_DELETION_COMPLETION_URL',
    defaultValue: 'https://xmo.dpdns.org/account/deleted',
  );

  /// Temporary rollback switch for pre-App-Link deployments only.
  static const enableLegacySsoCallback = bool.fromEnvironment(
    'XMO_ENABLE_LEGACY_SSO_CALLBACK',
    defaultValue: false,
  );

  static bool get isSsoLoginConfigured =>
      enableSsoLogin &&
      RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(ssoIdpId) &&
      _isValidSsoCallbackUrl(ssoCallbackUrl);

  static bool _isValidSsoCallbackUrl(String value) {
    final uri = Uri.tryParse(value.trim());
    if (uri == null || uri.query.isNotEmpty || uri.fragment.isNotEmpty) {
      return false;
    }
    if (uri.scheme == 'https' &&
        uri.host.toLowerCase() == 'xmo.dpdns.org' &&
        uri.path == '/auth/callback') {
      return true;
    }
    return enableLegacySsoCallback &&
        uri.scheme == 'xmo' &&
        uri.host == 'auth' &&
        uri.path == '/callback';
  }

  /// Public Reown client project identifier. Reown project IDs are shipped to
  /// clients by design; production access must be restricted in Reown's
  /// allowlist. A dart-define can replace this identifier without a code edit.
  static const reownProjectId = String.fromEnvironment(
    'XMO_REOWN_PROJECT_ID',
    defaultValue: 'aeb4b4a85b194d2c749a857947220b2d',
  );

  /// Public Thirdweb client identifier. Payment secrets remain server-side.
  static const thirdwebClientId = String.fromEnvironment(
    'XMO_THIRDWEB_CLIENT_ID',
    defaultValue: '81d97ee5ab262c8d202bc75ca83cc6f5',
  );

  static const pushGatewayUrl = String.fromEnvironment(
    'XMO_PUSH_GATEWAY_URL',
    defaultValue:
        'https://xmo-matrix.centralindia.cloudapp.azure.com/_matrix/push/v1/notify',
  );

  static const pushAppId = String.fromEnvironment(
    'XMO_PUSH_APP_ID',
    defaultValue: 'com.xmo.xmo',
  );

  static const pushProfileTag = String.fromEnvironment(
    'XMO_PUSH_PROFILE_TAG',
    defaultValue: 'mobile',
  );

  static const streamChunkStorage = String.fromEnvironment(
    'XMO_STREAM_CHUNK_STORAGE',
    defaultValue: 'matrix',
  );

  static const azureChunkSignUrl = String.fromEnvironment(
    'XMO_AZURE_CHUNK_SIGN_URL',
    defaultValue: '',
  );

  static const streamQualityMode = String.fromEnvironment(
    'XMO_STREAM_QUALITY_MODE',
    defaultValue: 'auto',
  );

  static bool get useAzureBlobChunks =>
      streamChunkStorage.toLowerCase() == 'azure' &&
      azureChunkSignUrl.trim().isNotEmpty;

  static List<String> productionConfigurationErrors() {
    final errors = <String>[];
    final httpsValues = <String, String>{
      'XMO_HOMESERVER_URL': homeserverUrl,
      'XMO_OTP_SERVER_URL': otpServerUrl,
      'XMO_USER_DIRECTORY_SERVER_URL': userDirectoryServerUrl,
      'XMO_ACCOUNT_DELETION_SERVER_URL': accountDeletionServerUrl,
      'XMO_INVITE_SERVER_URL': inviteServerUrl,
      'XMO_PUBLIC_WEBSITE_URL': publicWebsiteUrl,
      'XMO_ACCOUNT_DELETION_COMPLETION_URL': accountDeletionCompletionUrl,
      'XMO_SECURE_ACCOUNT_URL': secureAccountUrl,
      'XMO_MFA_SETUP_URL': mfaSetupUrl,
      'XMO_SECURE_ACCOUNT_RECOVERY_URL': secureAccountRecoveryUrl,
    };
    for (final entry in httpsValues.entries) {
      final uri = Uri.tryParse(entry.value.trim());
      if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) {
        errors.add('${entry.key} must be a valid HTTPS URL');
      }
    }
    if (!isSsoLoginConfigured) {
      errors.add(
        'Secure sign-in requires XMO_ENABLE_SSO_LOGIN=true, a valid '
        'XMO_SSO_IDP_ID, and the verified HTTPS XMO_SSO_CALLBACK_URL',
      );
    }
    if (streamChunkStorage.toLowerCase() == 'azure') {
      final uri = Uri.tryParse(azureChunkSignUrl.trim());
      if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) {
        errors.add('Azure chunk storage requires XMO_AZURE_CHUNK_SIGN_URL');
      }
    }
    return errors;
  }
}
