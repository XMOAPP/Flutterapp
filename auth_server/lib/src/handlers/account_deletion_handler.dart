part of xmo_auth_server;

const _accountDeletionTtl = Duration(minutes: 10);
final _activeAccountDeletionJobs = <String, Future<void>>{};
final _retryingAccountDeletionJobs = <String>{};

Uri _accountDeletionCompletionUri(String userId) {
  const fallback = 'https://xmo.dpdns.org/account/deleted';
  final configured =
      Platform.environment['XMO_ACCOUNT_DELETION_COMPLETION_URL'];
  final candidate = Uri.tryParse(
    configured == null || configured.trim().isEmpty ? fallback : configured,
  );
  final base =
      candidate != null &&
          candidate.scheme == 'https' &&
          candidate.host.toLowerCase() == 'xmo.dpdns.org' &&
          candidate.path == '/account/deleted'
      ? candidate
      : Uri.parse(fallback);
  return base.replace(
    queryParameters: {'xmo_action': 'account_deleted', 'user_id': userId},
  );
}

Future<void> _deleteXmoAccountData(HttpRequest request) async {
  final token = _userDirectoryBearerToken(request);
  if (token == null) {
    await _json(request, HttpStatus.unauthorized, {
      'success': false,
      'error': 'Missing XMO session token',
    });
    return;
  }

  final userId = await _userDirectoryWhoamiForRequest(request, token);
  await _acceptAccountDeletion(request, userId);
}

Future<void> _requestExternalAccountDeletion(HttpRequest request) async {
  final body = await _readJson(request);
  final username = _normalizeMatrixLocalpart(body['username']);
  final email = _normalizeEmail(body['email']);

  const genericResponse = {
    'success': true,
    'message': 'If the account details match, a deletion code was sent.',
  };
  if (!_isValidMatrixLocalpart(username) || !_isValidEmail(email)) {
    await _json(request, HttpStatus.ok, genericResponse);
    return;
  }
  if (!_passwordResetConfig.isConfigured || !_emailService.isConfigured) {
    await _json(request, HttpStatus.serviceUnavailable, {
      'success': false,
      'error': 'Account deletion is temporarily unavailable',
    });
    return;
  }
  final subject = _passwordResetKey(username, email);
  if (!await _consumeEmailOtpSendQuota(
    request,
    purpose: EmailOtpPurpose.externalAccountDeletion,
    subject: subject,
  )) {
    return;
  }

  final verified = await _isPasswordResetEmailVerified(
    username: username,
    email: email,
  );
  if (!verified) {
    await _json(request, HttpStatus.ok, genericResponse);
    return;
  }

  final otp = (_random.nextInt(900000) + 100000).toString();
  try {
    await _emailOtpStore.issue(
      purpose: EmailOtpPurpose.externalAccountDeletion,
      subject: subject,
      code: otp,
      expiresAt: DateTime.now().toUtc().add(_accountDeletionTtl),
    );
  } catch (error, stackTrace) {
    _logger.error('account_deletion_otp_issue_failed', error, stackTrace);
    await _json(request, HttpStatus.ok, genericResponse);
    return;
  }
  try {
    await _emailService.sendGenericEmail(
      to: email,
      subject: 'Confirm deletion of your XMO account',
      htmlContent:
          '''
        <div style="font-family:Arial,sans-serif;max-width:520px;margin:0 auto;padding:24px;text-align:center">
          <h2>Delete your XMO account</h2>
          <p>Enter this code on the XMO account deletion page.</p>
          <div style="font-size:32px;font-weight:700;letter-spacing:6px;margin:18px 0">$otp</div>
          <p>This code expires in 10 minutes.</p>
          <p style="color:#666;font-size:13px">If you did not request deletion, ignore this email and your account will remain active.</p>
        </div>
      ''',
      textContent:
          'Delete your XMO account\n\n'
          'Your deletion code is: $otp\n\n'
          'This code expires in 10 minutes. If you did not request deletion, '
          'ignore this email.',
      tag: 'account-deletion',
    );
  } on EmailDeliveryException catch (error) {
    await _removeEmailOtpChallenge(
      purpose: EmailOtpPurpose.externalAccountDeletion,
      subject: subject,
    );
    await _json(request, HttpStatus.badGateway, {'error': error.message});
    return;
  }

  await _json(request, HttpStatus.ok, genericResponse);
}

Future<void> _confirmExternalAccountDeletion(HttpRequest request) async {
  final body = await _readJson(request);
  final username = _normalizeMatrixLocalpart(body['username']);
  final email = _normalizeEmail(body['email']);
  final otp = body['otp']?.toString().trim() ?? '';
  if (!_isValidMatrixLocalpart(username) ||
      !_isValidEmail(email) ||
      !RegExp(r'^\d{6}$').hasMatch(otp)) {
    throw const _BadRequestException('Invalid deletion confirmation');
  }

  final subject = _passwordResetKey(username, email);
  if (!await _consumeEmailOtpVerificationQuota(
    request,
    purpose: EmailOtpPurpose.externalAccountDeletion,
  )) {
    return;
  }

  late final EmailOtpAttemptResult attempt;
  try {
    attempt = await _emailOtpStore.claimAttempt(
      purpose: EmailOtpPurpose.externalAccountDeletion,
      subject: subject,
      code: otp,
      maxAttempts: _maxAttempts,
      claimTtl: _emailOtpClaimTtl,
    );
  } catch (error, stackTrace) {
    _logger.error('account_deletion_otp_claim_failed', error, stackTrace);
    await _json(request, HttpStatus.serviceUnavailable, {
      'success': false,
      'error': 'Account deletion is temporarily unavailable',
    });
    return;
  }

  switch (attempt.status) {
    case EmailOtpAttemptStatus.valid:
      break;
    case EmailOtpAttemptStatus.notRequested:
      await _json(request, HttpStatus.badRequest, {
        'success': false,
        'error': 'Deletion code was not requested',
      });
      return;
    case EmailOtpAttemptStatus.expired:
      await _json(request, HttpStatus.badRequest, {
        'success': false,
        'error': 'Deletion code expired',
      });
      return;
    case EmailOtpAttemptStatus.tooManyAttempts:
      await _json(request, HttpStatus.tooManyRequests, {
        'success': false,
        'error': 'Too many deletion attempts',
      });
      return;
    case EmailOtpAttemptStatus.incorrectCode:
      await _json(request, HttpStatus.badRequest, {
        'success': false,
        'error': 'Incorrect deletion code',
      });
      return;
    case EmailOtpAttemptStatus.alreadyProcessing:
      await _json(request, HttpStatus.conflict, {
        'success': false,
        'error': 'Account deletion is already being processed',
      });
      return;
  }

  final verified = await _isPasswordResetEmailVerified(
    username: username,
    email: email,
  );
  if (!verified) {
    await _removeEmailOtpChallenge(
      purpose: EmailOtpPurpose.externalAccountDeletion,
      subject: subject,
    );
    await _json(request, HttpStatus.forbidden, {
      'success': false,
      'error': 'Email is not verified for this account',
    });
    return;
  }

  final userId = _matrixUserId(username);
  try {
    await _emailOtpStore.remove(
      purpose: EmailOtpPurpose.externalAccountDeletion,
      subject: subject,
    );
  } catch (error, stackTrace) {
    try {
      await _emailOtpStore.releaseClaim(
        purpose: EmailOtpPurpose.externalAccountDeletion,
        subject: subject,
      );
    } catch (releaseError, releaseStackTrace) {
      _logger.error(
        'account_deletion_otp_release_failed',
        releaseError,
        releaseStackTrace,
      );
    }
    _logger.error('account_deletion_otp_consume_failed', error, stackTrace);
    await _json(request, HttpStatus.serviceUnavailable, {
      'success': false,
      'error': 'Account deletion is temporarily unavailable',
    });
    return;
  }
  await _acceptAccountDeletion(request, userId);
}

Future<void> _acceptAccountDeletion(HttpRequest request, String userId) async {
  if (!_passwordResetConfig.isConfigured || !_authentikConfig.isConfigured) {
    await _json(request, HttpStatus.serviceUnavailable, {
      'success': false,
      'error': 'Account deletion is temporarily unavailable',
    });
    return;
  }
  final normalized = _userDirectoryNormalizeUserId(userId);
  if (normalized == null) {
    throw const _BadRequestException('Invalid XMO account ID');
  }
  final username = _userDirectoryLocalpartFromUserId(normalized);
  final job = _accountDeletionJobs.begin(
    userId: normalized,
    username: username,
  );
  if (!job.isComplete) {
    _scheduleAccountDeletionRetry(normalized, initialDelay: Duration.zero);
  }
  await _json(request, job.isComplete ? HttpStatus.ok : HttpStatus.accepted, {
    'success': true,
    'status': job.isComplete ? 'complete' : 'processing',
    'user_id': normalized,
    'return_url': _accountDeletionCompletionUri(normalized).toString(),
    if (!job.isComplete)
      'message': 'Account deletion was accepted and is processing.',
  });
}

Future<void> _runAccountDeletionJob(String userId) {
  final active = _activeAccountDeletionJobs[userId];
  if (active != null) return active;

  late final Future<void> tracked;
  tracked = _performAccountDeletionJob(userId).whenComplete(() {
    if (identical(_activeAccountDeletionJobs[userId], tracked)) {
      _activeAccountDeletionJobs.remove(userId);
    }
  });
  _activeAccountDeletionJobs[userId] = tracked;
  return tracked;
}

Future<void> _performAccountDeletionJob(String userId) async {
  var job = _accountDeletionJobs.get(userId);
  if (job == null || job.isComplete) return;

  if (job.phase.index < AccountDeletionPhase.mediaDeleted.index) {
    await _deleteSynapseUserMedia(job.userId);
    job = _accountDeletionJobs.advance(
      job.userId,
      AccountDeletionPhase.mediaDeleted,
    );
  }
  if (job.phase.index < AccountDeletionPhase.synapseDeactivated.index) {
    await _deactivateSynapseAccount(job.userId);
    job = _accountDeletionJobs.advance(
      job.userId,
      AccountDeletionPhase.synapseDeactivated,
    );
  }
  if (job.phase.index < AccountDeletionPhase.authentikDeleted.index) {
    await _authentikDeleteAccount(job.username);
    job = _accountDeletionJobs.advance(
      job.userId,
      AccountDeletionPhase.authentikDeleted,
    );
  }
  if (job.phase.index < AccountDeletionPhase.recordsPurged.index) {
    await _purgeXmoAccountRecords(job.userId);
    job = _accountDeletionJobs.advance(
      job.userId,
      AccountDeletionPhase.recordsPurged,
    );
  }
  _accountDeletionJobs.advance(job.userId, AccountDeletionPhase.complete);
  logInfo('account_deletion_completed');
}

void _resumePendingAccountDeletionJobs() {
  for (final job in _accountDeletionJobs.pending) {
    _scheduleAccountDeletionRetry(job.userId, initialDelay: Duration.zero);
  }
}

void _scheduleAccountDeletionRetry(
  String userId, {
  Duration initialDelay = const Duration(seconds: 2),
}) {
  if (!_retryingAccountDeletionJobs.add(userId)) return;
  unawaited(() async {
    var delay = initialDelay;
    try {
      while (_accountDeletionJobs.get(userId)?.isComplete == false) {
        if (delay > Duration.zero) await Future<void>.delayed(delay);
        try {
          await _runAccountDeletionJob(userId);
        } catch (error, st) {
          _accountDeletionJobs.recordFailure(userId, error);
          _logger.error('account_deletion_retry_failed', error, st);
          final nextSeconds =
              (delay.inSeconds <= 0 ? 5 : (delay.inSeconds * 2).clamp(5, 300))
                  .toInt();
          delay = Duration(seconds: nextSeconds);
        }
      }
    } finally {
      _retryingAccountDeletionJobs.remove(userId);
    }
  }());
}

Future<void> _deleteSynapseUserMedia(String userId) async {
  const maxBatches = 1000;
  for (var batch = 0; batch < maxBatches; batch++) {
    final response = await _synapseRequest(
      method: 'DELETE',
      pathSegments: ['_synapse', 'admin', 'v1', 'users', userId, 'media'],
      queryParameters: const {'limit': '100'},
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException(
        'Synapse media deletion failed: ${response.statusCode}',
      );
    }
    final body = _decodeJsonMap(response.body);
    final deleted = _asList(body['deleted_media']) ?? const [];
    if (deleted.isEmpty) return;
  }
  throw const HttpException(
    'Synapse media deletion exceeded the safety batch limit',
  );
}

Future<void> _deactivateSynapseAccount(String userId) async {
  final response = await _synapseRequest(
    method: 'POST',
    pathSegments: ['_synapse', 'admin', 'v1', 'deactivate', userId],
    body: {'erase': true},
  );
  if (response.statusCode < 200 || response.statusCode >= 300) {
    throw HttpException(
      'Synapse account deactivation failed: ${response.statusCode}',
    );
  }
}

Future<void> _purgeXmoAccountRecords(String userId) async {
  final normalized = _userDirectoryNormalizeUserId(userId);
  if (normalized == null) {
    throw const _BadRequestException('Invalid XMO account ID');
  }
  final localpart = _userDirectoryLocalpartFromUserId(normalized);

  final directory = await _readUserDirectoryEntries();
  directory.remove(localpart);
  await _writeUserDirectoryEntries(directory);

  final email = _recoveryEmailStore.removeVerified(localpart);

  if (_passwordResetStoreReady) {
    await _passwordResetStore.removeForUsername(localpart);
  }
  if (_emailOtpStoreReady) {
    if (email != null) {
      await _removeEmailOtpChallenge(
        purpose: EmailOtpPurpose.registration,
        subject: email,
      );
      await _removeEmailOtpChallenge(
        purpose: EmailOtpPurpose.externalAccountDeletion,
        subject: _passwordResetKey(localpart, email),
      );
    }
  }
  if (_walletAccountStoreReady) {
    await _walletAccountStore.removeUsername(localpart);
  }

  await _withReportStore((reports) {
    reports.removeWhere(
      (_, report) =>
          report.reporterUserId == normalized ||
          report.reportedUserId == normalized ||
          report.reviewedBy == normalized,
    );
    return null;
  });
  await _deleteChannelAnalyticsForUser(normalized);
  await _deleteInviteLinksForUser(normalized);
}

Future<void> _serveAccountDeletionPage(HttpRequest request) async {
  request.response
    ..statusCode = HttpStatus.ok
    ..headers.contentType = ContentType.html
    ..headers.set('Cache-Control', 'no-store')
    ..headers.set(
      'Content-Security-Policy',
      "default-src 'self'; style-src 'unsafe-inline'; script-src 'unsafe-inline'; connect-src 'self'; frame-ancestors 'none'",
    )
    ..write(_accountDeletionHtml);
  await request.response.close();
}

const _accountDeletionHtml = r'''<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Delete XMO account</title><style>
body{margin:0;background:#080d11;color:#f7f7f7;font:16px Arial,sans-serif}main{max-width:560px;margin:0 auto;padding:48px 22px}h1{font-size:28px}p,li{color:#aeb4ba;line-height:1.55}.panel{background:#12181e;padding:22px;border-radius:8px;margin:22px 0}label{display:block;margin:16px 0 7px}input{box-sizing:border-box;width:100%;padding:13px 15px;border:1px solid #555;border-radius:8px;background:#29292c;color:#fff;font-size:16px}button,.button{display:inline-block;margin-top:20px;padding:13px 20px;border:0;border-radius:8px;background:#fff;color:#080d11;font-weight:700;cursor:pointer;text-decoration:none}button:disabled{opacity:.5}#confirm,#return{display:none}.status{margin-top:16px;color:#aeb4ba}.danger{color:#ff8585}a{color:#9bea38}
</style></head><body><main><h1>Delete your XMO account</h1>
<p>This page lets you request account deletion without reinstalling XMO.</p>
<div class="panel"><strong>Deletion removes:</strong><ul><li>Your secure sign-in identity, Matrix account, active sessions, devices, security keys and profile.</li><li>Your XMO public-directory, recovery, report, invite and analytics records.</li></ul>
<p class="danger">Messages or media already delivered to other users, devices, or connected servers may remain. Uploaded media may remain under server retention rules.</p></div>
<section id="request"><label for="username">XMO username</label><input id="username" placeholder="@username" autocomplete="username"><label for="email">Verified email</label><input id="email" type="email" placeholder="you@example.com" autocomplete="email"><button id="send">Send deletion code</button></section>
<section id="confirm"><label for="otp">6-digit deletion code</label><input id="otp" inputmode="numeric" maxlength="6" placeholder="000000"><button id="delete">Permanently delete account</button></section>
<div id="status" class="status" aria-live="polite"></div><p id="return"><a id="returnLink" class="button" href="#">Return to XMO</a></p><p>Need help? <a href="mailto:support@xmo.dpdns.org">support@xmo.dpdns.org</a></p>
<script>
const $=id=>document.getElementById(id),status=$('status');async function post(path,body){const r=await fetch(path,{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(body)});const data=await r.json();if(!r.ok||data.success===false)throw new Error(data.error||'Request failed');return data}
$('send').onclick=async()=>{status.textContent='Sending...';$('send').disabled=true;try{const data=await post('/account-deletion/request',{username:$('username').value,email:$('email').value});status.textContent=data.message;$('confirm').style.display='block'}catch(e){status.textContent=e.message}finally{$('send').disabled=false}};
$('delete').onclick=async()=>{if(!confirm('Permanently delete this XMO account? This cannot be undone.'))return;status.textContent='Deleting...';$('delete').disabled=true;try{const data=await post('/account-deletion/confirm',{username:$('username').value,email:$('email').value,otp:$('otp').value});status.textContent=data.status==='processing'?'Deletion is processing. Returning to XMO...':'Your XMO account has been deleted. Returning to XMO...';if(data.return_url){$('returnLink').href=data.return_url;$('return').style.display='block';if(/Android/i.test(navigator.userAgent)){setTimeout(()=>{location.href=data.return_url},700)}}$('request').style.display='none';$('confirm').style.display='none'}catch(e){status.textContent=e.message;$('delete').disabled=false}};
</script></main></body></html>''';
