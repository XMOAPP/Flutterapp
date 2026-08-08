part of xmo_auth_server;

const _accountDeletionTtl = Duration(minutes: 10);

Future<void> _deleteXmoAccountData(HttpRequest request) async {
  final token = _userDirectoryBearerToken(request);
  if (token == null) {
    await _json(request, HttpStatus.unauthorized, {
      'success': false,
      'error': 'Missing XMO session token',
    });
    return;
  }

  final userId = await _userDirectoryWhoami(token);
  await _deleteSynapseUserMedia(userId);
  await _purgeXmoAccountRecords(userId);
  await _json(request, HttpStatus.ok, {'success': true});
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

  final verified = await _isPasswordResetEmailVerified(
    username: username,
    email: email,
  );
  if (!verified) {
    await _json(request, HttpStatus.ok, genericResponse);
    return;
  }

  final otp = (_random.nextInt(900000) + 100000).toString();
  _accountDeletionStore[_passwordResetKey(username, email)] =
      _AccountDeletionRecord(
    code: otp,
    expiresAt: DateTime.now().toUtc().add(_accountDeletionTtl),
  );
  try {
    await _emailService.sendGenericEmail(
      to: email,
      subject: 'Confirm deletion of your XMO account',
      htmlContent: '''
        <div style="font-family:Arial,sans-serif;max-width:520px;margin:0 auto;padding:24px;text-align:center">
          <h2>Delete your XMO account</h2>
          <p>Enter this code on the XMO account deletion page.</p>
          <div style="font-size:32px;font-weight:700;letter-spacing:6px;margin:18px 0">$otp</div>
          <p>This code expires in 10 minutes.</p>
          <p style="color:#666;font-size:13px">If you did not request deletion, ignore this email and your account will remain active.</p>
        </div>
      ''',
      textContent: 'Delete your XMO account\n\n'
          'Your deletion code is: $otp\n\n'
          'This code expires in 10 minutes. If you did not request deletion, '
          'ignore this email.',
      tag: 'account-deletion',
    );
  } on EmailDeliveryException catch (error) {
    _accountDeletionStore.remove(_passwordResetKey(username, email));
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
      otp.length != 6) {
    throw const _BadRequestException('Invalid deletion confirmation');
  }

  final key = _passwordResetKey(username, email);
  final record = _accountDeletionStore[key];
  if (record == null) {
    await _json(request, HttpStatus.badRequest, {
      'success': false,
      'error': 'Deletion code was not requested',
    });
    return;
  }
  if (DateTime.now().toUtc().isAfter(record.expiresAt)) {
    _accountDeletionStore.remove(key);
    await _json(request, HttpStatus.badRequest, {
      'success': false,
      'error': 'Deletion code expired',
    });
    return;
  }
  record.attempts += 1;
  if (record.attempts > _maxAttempts) {
    _accountDeletionStore.remove(key);
    await _json(request, HttpStatus.tooManyRequests, {
      'success': false,
      'error': 'Too many deletion attempts',
    });
    return;
  }
  if (record.code != otp) {
    await _json(request, HttpStatus.badRequest, {
      'success': false,
      'error': 'Incorrect deletion code',
    });
    return;
  }

  final verified = await _isPasswordResetEmailVerified(
    username: username,
    email: email,
  );
  if (!verified) {
    _accountDeletionStore.remove(key);
    await _json(request, HttpStatus.forbidden, {
      'success': false,
      'error': 'Email is not verified for this account',
    });
    return;
  }

  final userId = _matrixUserId(username);
  await _deactivateSynapseAccount(userId);
  await _deleteSynapseUserMedia(userId);
  await _purgeXmoAccountRecords(userId);
  _accountDeletionStore.remove(key);
  await _json(request, HttpStatus.ok, {'success': true});
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
  try {
    await _authentikDeactivateUser(localpart);
  } catch (error, st) {
    _logger.error('authentik_user_deactivation_failed', error, st);
  }

  final directory = await _readUserDirectoryEntries();
  directory.remove(localpart);
  await _writeUserDirectoryEntries(directory);

  final remembered = await _readRememberedPasswordResetEmails();
  final email = remembered.remove(localpart);
  await _writeRememberedPasswordResetEmails(remembered);

  _passwordResetStore.removeWhere(
    (key, _) => key.startsWith('$localpart|'),
  );
  _accountDeletionStore.removeWhere(
    (key, _) => key.startsWith('$localpart|'),
  );
  if (email != null) _otpStore.remove(email);
  _walletAuthService.removeChallengesForUsername(localpart);

  await _withReportStore((reports) {
    reports.removeWhere((_, report) =>
        report.reporterUserId == normalized ||
        report.reportedUserId == normalized ||
        report.reviewedBy == normalized);
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
body{margin:0;background:#080d11;color:#f7f7f7;font:16px Arial,sans-serif}main{max-width:560px;margin:0 auto;padding:48px 22px}h1{font-size:28px}p,li{color:#aeb4ba;line-height:1.55}.panel{background:#12181e;padding:22px;border-radius:8px;margin:22px 0}label{display:block;margin:16px 0 7px}input{box-sizing:border-box;width:100%;padding:13px 15px;border:1px solid #555;border-radius:8px;background:#29292c;color:#fff;font-size:16px}button{margin-top:20px;padding:13px 20px;border:0;border-radius:8px;background:#fff;color:#080d11;font-weight:700;cursor:pointer}button:disabled{opacity:.5}#confirm{display:none}.status{margin-top:16px;color:#aeb4ba}.danger{color:#ff8585}a{color:#9bea38}
</style></head><body><main><h1>Delete your XMO account</h1>
<p>This page lets you request account deletion without reinstalling XMO.</p>
<div class="panel"><strong>Deletion removes:</strong><ul><li>Your XMO login, devices, security keys, notifications, profile and room memberships where the service can erase them.</li><li>Your XMO public-directory, password-recovery and report records.</li></ul>
<p class="danger">Messages or media already delivered to other users, devices, or connected servers may remain. Uploaded media may remain under server retention rules.</p></div>
<section id="request"><label for="username">XMO username</label><input id="username" placeholder="@username" autocomplete="username"><label for="email">Verified email</label><input id="email" type="email" placeholder="you@example.com" autocomplete="email"><button id="send">Send deletion code</button></section>
<section id="confirm"><label for="otp">6-digit deletion code</label><input id="otp" inputmode="numeric" maxlength="6" placeholder="000000"><button id="delete">Permanently delete account</button></section>
<div id="status" class="status" aria-live="polite"></div><p>Need help? <a href="mailto:support@xmo.dpdns.org">support@xmo.dpdns.org</a></p>
<script>
const $=id=>document.getElementById(id),status=$('status');async function post(path,body){const r=await fetch(path,{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(body)});const data=await r.json();if(!r.ok||data.success===false)throw new Error(data.error||'Request failed');return data}
$('send').onclick=async()=>{status.textContent='Sending...';$('send').disabled=true;try{const data=await post('/account-deletion/request',{username:$('username').value,email:$('email').value});status.textContent=data.message;$('confirm').style.display='block'}catch(e){status.textContent=e.message}finally{$('send').disabled=false}};
$('delete').onclick=async()=>{if(!confirm('Permanently delete this XMO account? This cannot be undone.'))return;status.textContent='Deleting...';$('delete').disabled=true;try{await post('/account-deletion/confirm',{username:$('username').value,email:$('email').value,otp:$('otp').value});status.textContent='Your XMO account has been deleted.';$('request').style.display='none';$('confirm').style.display='none'}catch(e){status.textContent=e.message;$('delete').disabled=false}};
</script></main></body></html>''';

class _AccountDeletionRecord {
  _AccountDeletionRecord({required this.code, required this.expiresAt});
  final String code;
  final DateTime expiresAt;
  int attempts = 0;
}
