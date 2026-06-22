Map<String, dynamic> buildHealthStatus({
  required bool emailConfigured,
  required bool donationConfigured,
  required bool pushConfigured,
}) =>
    {
      'ok': true,
      'status': 'ready',
      'services': {
        'otp': emailConfigured ? 'ready' : 'not_configured',
        'donations': donationConfigured ? 'ready' : 'not_configured',
        'push': pushConfigured ? 'ready' : 'not_configured',
      },
    };
