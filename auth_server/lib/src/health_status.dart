Map<String, dynamic> buildHealthStatus({
  required bool emailConfigured,
  required bool donationConfigured,
  required bool walletAuthConfigured,
  required bool passwordResetConfigured,
  required bool pushConfigured,
  required bool azureBlobConfigured,
  required bool userDirectoryConfigured,
}) =>
    {
      'ok': true,
      'status': 'ready',
      'services': {
        'otp': emailConfigured ? 'ready' : 'not_configured',
        'donations': donationConfigured ? 'ready' : 'not_configured',
        'walletAuth': walletAuthConfigured ? 'ready' : 'not_configured',
        'passwordReset': passwordResetConfigured ? 'ready' : 'not_configured',
        'push': pushConfigured ? 'ready' : 'not_configured',
        'azureBlob': azureBlobConfigured ? 'ready' : 'not_configured',
        'userDirectory': userDirectoryConfigured ? 'ready' : 'not_configured',
      },
    };
