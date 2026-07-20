Map<String, dynamic> buildHealthStatus({
  required bool emailConfigured,
  required bool donationConfigured,
  required bool walletAuthConfigured,
  required bool passwordResetConfigured,
  required bool pushConfigured,
  required bool azureBlobConfigured,
  required bool userDirectoryConfigured,
  required bool reportsConfigured,
  required bool accountDeletionConfigured,
  required bool channelAnalyticsConfigured,
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
        'reports': reportsConfigured ? 'ready' : 'not_configured',
        'accountDeletion':
            accountDeletionConfigured ? 'ready' : 'not_configured',
        'channelAnalytics':
            channelAnalyticsConfigured ? 'ready' : 'not_configured',
      },
    };
