library xmo_auth_server;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:cryptography/cryptography.dart' as cryptography;
import 'package:googleapis_auth/auth_io.dart';

import 'package:xmo_auth_server/src/account_deletion_job_store.dart';
import 'package:xmo_auth_server/src/cors_policy.dart';
import 'package:xmo_auth_server/src/email_service.dart';
import 'package:xmo_auth_server/src/endpoint_modules.dart';
import 'package:xmo_auth_server/src/health_status.dart';
import 'package:xmo_auth_server/src/password_policy.dart';
import 'package:xmo_auth_server/src/password_reset_store.dart';
import 'package:xmo_auth_server/src/request_body.dart';
import 'package:xmo_auth_server/src/request_guard.dart';
import 'package:xmo_auth_server/src/recovery_email_store.dart';
import 'package:xmo_auth_server/src/room_capacity_policy.dart';
import 'package:xmo_auth_server/src/secure_login_enrollment_proof_store.dart';
import 'package:xmo_auth_server/src/structured_logger.dart';
import 'package:xmo_auth_server/src/wallet_auth_service.dart';
import 'package:xmo_auth_server/src/wallet_account_store.dart';

part '../lib/src/handlers/azure_blob_handler.dart';
part '../lib/src/handlers/account_deletion_handler.dart';
part '../lib/src/handlers/authentik_provisioning_handler.dart';
part '../lib/src/handlers/channel_analytics_handler.dart';
part '../lib/src/handlers/donation_handler.dart';
part '../lib/src/handlers/invite_handler.dart';
part '../lib/src/handlers/otp_handler.dart';
part '../lib/src/handlers/password_reset_handler.dart';
part '../lib/src/handlers/push_handler.dart';
part '../lib/src/handlers/report_handler.dart';
part '../lib/src/handlers/recovery_email_handler.dart';
part '../lib/src/handlers/user_directory_handler.dart';
part '../lib/src/handlers/wallet_handler.dart';
part '../lib/src/request_authorization.dart';

final int _port = int.tryParse(Platform.environment['PORT'] ?? '') ?? 3000;
final String _thirdwebSecretKey =
    Platform.environment['XMO_THIRDWEB_SECRET_KEY'] ?? '';
final String _donationRecipientAddress =
    Platform.environment['XMO_DONATION_RECIPIENT_ADDRESS'] ??
    _defaultDonationRecipientAddress;
final String _firebaseServiceAccountJson =
    Platform.environment['XMO_FIREBASE_SERVICE_ACCOUNT_JSON'] ?? '';
final String _firebaseServiceAccountBase64 =
    Platform.environment['XMO_FIREBASE_SERVICE_ACCOUNT_BASE64'] ?? '';
final String _firebaseServiceAccountFile =
    Platform.environment['XMO_FIREBASE_SERVICE_ACCOUNT_FILE'] ?? '';
final String _firebaseProjectId =
    Platform.environment['XMO_FIREBASE_PROJECT_ID'] ?? '';

final _otpStore = <String, _OtpRecord>{};
final _secureLoginEnrollmentProofs = SecureLoginEnrollmentProofStore(
  ttl: _secureLoginEnrollmentProofTtl,
  storageFile: File(
    Platform.environment['XMO_SECURE_LOGIN_ENROLLMENT_STORE_FILE'] ??
        '/app/data/secure_login_enrollment_proofs.json',
  ),
);
final _random = Random.secure();
final _trustedProxyConfig = TrustedProxyConfig.fromEnvironment(
  Platform.environment,
);
final _corsPolicy = CorsPolicy.fromEnvironment(Platform.environment);
final _rateLimiter = RequestRateLimiter(trustedProxies: _trustedProxyConfig);
const _logger = StructuredLogger();
final _emailConfig = EmailConfig.fromEnvironment(Platform.environment);
final _emailService = EmailService(config: _emailConfig, logger: _logger);
final _passwordResetConfig = PasswordResetConfig.fromEnvironment(
  Platform.environment,
);
final _passwordResetStore = PasswordResetStore(
  config: PasswordResetStoreConfig.fromEnvironment(Platform.environment),
);
var _passwordResetStoreReady = false;
final _recoveryEmailStore = RecoveryEmailStore(
  ttl: _secureLoginEnrollmentProofTtl,
  storageFile: _passwordResetConfig.recoveryEmailStorageFile,
);
final _walletAuthService = WalletAuthService(
  config: WalletAuthConfig.fromEnvironment(Platform.environment),
);
final _walletAccountStore = WalletAccountStore(
  config: WalletAccountStoreConfig.fromEnvironment(Platform.environment),
);
var _walletAccountStoreReady = false;
final _azureBlobConfig = AzureBlobConfig.fromEnvironment(Platform.environment);
final _reportConfig = ReportConfig.fromEnvironment(Platform.environment);
final _accountDeletionStore = <String, _AccountDeletionRecord>{};
final _accountDeletionJobs = AccountDeletionJobStore(
  storageFile: File(
    Platform.environment['XMO_ACCOUNT_DELETION_STORE_FILE'] ??
        '/app/data/account_deletion_jobs.json',
  ),
);
final _inviteConfig = InviteConfig.fromEnvironment(Platform.environment);
const _otpEndpoints = OtpEndpointModule(send: _sendOtp, verify: _verifyOtp);
const _passwordResetEndpoints = PasswordResetEndpointModule(
  start: _startPasswordReset,
  complete: _completePasswordReset,
);
const _recoveryEmailEndpoints = RecoveryEmailEndpointModule(
  prepareLocalEnrollment: _prepareLocalRecoveryEmailEnrollment,
  completeLocalEnrollment: _completeLocalRecoveryEmailEnrollment,
  startChange: _startRecoveryEmailChange,
  confirmChange: _confirmRecoveryEmailChange,
);
const _donationEndpoints = DonationEndpointModule(_createDonationPayment);
const _inviteEndpoints = InviteEndpointModule(
  create: _createInviteLink,
  list: _listInviteLinks,
  revoke: _revokeInviteLink,
  preview: _previewInviteLink,
  avatar: _serveInviteAvatar,
  redeem: _redeemInviteLink,
);
const _walletEndpoints = WalletEndpointModule(
  account: _getWalletAccount,
  session: _getWalletSession,
  usernameAvailability: _checkWalletUsernameAvailability,
  nonce: _createWalletNonce,
  verify: _verifyWalletSignature,
);
const _azureBlobEndpoints = AzureBlobEndpointModule(
  signUpload: _signAzureBlobChunkUpload,
  download: _downloadAzureBlobChunk,
);
const _userDirectoryEndpoints = UserDirectoryEndpointModule(
  upsert: _upsertUserDirectoryEntry,
  search: _searchUserDirectory,
  checkUsernameAvailability: _checkOidcUsernameAvailability,
  registerOidcAccount: _registerOidcAccount,
  prepareSecureRegistration: _prepareSecureRegistration,
  provisionSecureLogin: _provisionSecureLogin,
);
const _reportEndpoints = ReportEndpointModule(
  submit: _submitReport,
  list: _listReports,
  update: _updateReport,
);
const _accountDeletionEndpoints = AccountDeletionEndpointModule(
  deleteData: _deleteXmoAccountData,
  requestExternal: _requestExternalAccountDeletion,
  confirmExternal: _confirmExternalAccountDeletion,
);
const _channelAnalyticsEndpoints = ChannelAnalyticsEndpointModule(
  view: _recordChannelView,
  forward: _recordChannelForward,
  stats: _getChannelAnalytics,
);
const _pushEndpoints = PushGatewayEndpointModule(_handleMatrixPush);
const _endpointAuthorization = EndpointAuthorizationRegistry(
  otp: _otpEndpoints,
  passwordReset: _passwordResetEndpoints,
  recoveryEmail: _recoveryEmailEndpoints,
  donation: _donationEndpoints,
  invite: _inviteEndpoints,
  wallet: _walletEndpoints,
  azureBlob: _azureBlobEndpoints,
  userDirectory: _userDirectoryEndpoints,
  reports: _reportEndpoints,
  accountDeletion: _accountDeletionEndpoints,
  channelAnalytics: _channelAnalyticsEndpoints,
  push: _pushEndpoints,
);

const _otpTtl = Duration(minutes: 1);
const _secureLoginEnrollmentProofTtl = Duration(minutes: 5);
const _passwordResetTtl = Duration(minutes: 5);
const _passwordResetClaimTtl = Duration(minutes: 2);
const _maxAttempts = 5;
const _thirdwebBaseUrl = 'https://api.thirdweb.com';
const _baseUsdcAddress = '0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913';
const _defaultDonationRecipientAddress =
    '0xc1a4BF16f64f5eE26b7C73831eF8bc70f200EacB';
const _baseChainId = 8453;
const _minDonationUsd = 5.0;
const _firebaseMessagingScope =
    'https://www.googleapis.com/auth/firebase.messaging';

Future<void> main() async {
  if (_passwordResetStore.config.isConfigured) {
    try {
      await _passwordResetStore.initialize();
      _passwordResetStoreReady = true;
      logInfo('password_reset_store_ready');
    } catch (error, stackTrace) {
      _logger.error(
        'password_reset_store_initialization_failed',
        error,
        stackTrace,
      );
    }
  }
  if (_walletAccountStore.config.isConfigured &&
      _walletAuthService.config.isConfigured) {
    try {
      await _walletAccountStore.initialize();
      _walletAccountStoreReady = true;
      logInfo('wallet_account_store_ready');
    } catch (error, stackTrace) {
      _logger.error(
        'wallet_account_store_initialization_failed',
        error,
        stackTrace,
      );
    }
  }
  final server = await HttpServer.bind(InternetAddress.anyIPv4, _port);
  stdout.writeln('XMO auth server listening on 0.0.0.0:$_port');
  _resumePendingAccountDeletionJobs();

  await for (final request in server) {
    await _handleRequest(request);
  }
}

Future<void> _handleRequest(HttpRequest request) async {
  final stopwatch = Stopwatch()..start();

  try {
    final origin = request.headers.value('origin');
    if (origin != null && !_corsPolicy.allowsOrigin(origin)) {
      await _json(request, HttpStatus.forbidden, {
        'error': 'Cross-origin request is not allowed',
      });
      return;
    }

    if (request.method == 'OPTIONS') {
      if (origin != null &&
          !_corsPolicy.allowsPreflight(
            requestMethod: request.headers.value(
              'access-control-request-method',
            ),
            requestHeaders: request.headers.value(
              'access-control-request-headers',
            ),
          )) {
        request.response.statusCode = HttpStatus.forbidden;
        await request.response.close();
        return;
      }
      if (origin != null) {
        _corsPolicy.applyHeaders(request.response, origin);
      }
      request.response.statusCode = HttpStatus.noContent;
      await request.response.close();
      return;
    }

    if (origin != null) {
      _corsPolicy.applyHeaders(request.response, origin);
    }

    final invitePreview =
        request.method == 'GET' &&
        _inviteEndpoints.handlesPreview(request.uri.path);
    final inviteAvatar =
        request.method == 'GET' &&
        _inviteEndpoints.handlesAvatar(request.uri.path);
    final inviteRedeem =
        request.method == 'POST' &&
        _inviteEndpoints.handlesRedeem(request.uri.path);
    final rateLimitRoute = invitePreview
        ? '/invites/:token/preview'
        : inviteAvatar
        ? '/invites/:token/avatar'
        : inviteRedeem
        ? '/invites/:token/redeem'
        : null;
    if ((request.method == 'POST' || invitePreview || inviteAvatar) &&
        !_rateLimiter.allow(request, routeKey: rateLimitRoute)) {
      await _json(request, HttpStatus.tooManyRequests, {
        'error': 'Too many requests. Please try again shortly.',
      });
      return;
    }

    final authorizationPolicy = _endpointAuthorization.policyFor(
      method: request.method,
      path: request.uri.path,
    );
    if (authorizationPolicy == null) {
      await _json(request, HttpStatus.notFound, {'error': 'Not found'});
      return;
    }
    if (!await _authorizeEndpoint(request, authorizationPolicy)) return;

    if (request.method == 'GET' && request.uri.path == '/health') {
      await _json(request, HttpStatus.ok, buildHealthStatus());
      return;
    }

    if (request.method == 'GET' && request.uri.path == '/account-deletion') {
      await _serveAccountDeletionPage(request);
      return;
    }

    if (request.method == 'POST' &&
        _accountDeletionEndpoints.handlesDeleteData(request.uri.path)) {
      await _accountDeletionEndpoints.deleteData(request);
      return;
    }

    if (request.method == 'POST' &&
        _inviteEndpoints.handlesCreate(request.uri.path)) {
      await _inviteEndpoints.create(request);
      return;
    }
    if (request.method == 'POST' &&
        _inviteEndpoints.handlesList(request.uri.path)) {
      await _inviteEndpoints.list(request);
      return;
    }
    if (request.method == 'POST' &&
        _inviteEndpoints.handlesRevoke(request.uri.path)) {
      await _inviteEndpoints.revoke(request);
      return;
    }
    if (request.method == 'GET' &&
        _inviteEndpoints.handlesPreview(request.uri.path)) {
      await _inviteEndpoints.preview(request);
      return;
    }
    if (request.method == 'GET' &&
        _inviteEndpoints.handlesAvatar(request.uri.path)) {
      await _inviteEndpoints.avatar(request);
      return;
    }
    if (request.method == 'POST' &&
        _inviteEndpoints.handlesRedeem(request.uri.path)) {
      await _inviteEndpoints.redeem(request);
      return;
    }

    if (request.method == 'POST' &&
        _channelAnalyticsEndpoints.handlesView(request.uri.path)) {
      await _channelAnalyticsEndpoints.view(request);
      return;
    }
    if (request.method == 'POST' &&
        _channelAnalyticsEndpoints.handlesForward(request.uri.path)) {
      await _channelAnalyticsEndpoints.forward(request);
      return;
    }
    if (request.method == 'POST' &&
        _channelAnalyticsEndpoints.handlesStats(request.uri.path)) {
      await _channelAnalyticsEndpoints.stats(request);
      return;
    }

    if (request.method == 'POST' &&
        _accountDeletionEndpoints.handlesExternalRequest(request.uri.path)) {
      await _accountDeletionEndpoints.requestExternal(request);
      return;
    }

    if (request.method == 'POST' &&
        _accountDeletionEndpoints.handlesExternalConfirm(request.uri.path)) {
      await _accountDeletionEndpoints.confirmExternal(request);
      return;
    }

    if (request.method == 'POST' &&
        _otpEndpoints.handlesSend(request.uri.path)) {
      await _otpEndpoints.send(request);
      return;
    }

    if (request.method == 'POST' &&
        _otpEndpoints.handlesVerify(request.uri.path)) {
      await _otpEndpoints.verify(request);
      return;
    }

    if (request.method == 'POST' &&
        _recoveryEmailEndpoints.handlesPrepareLocalEnrollment(
          request.uri.path,
        )) {
      await _recoveryEmailEndpoints.prepareLocalEnrollment(request);
      return;
    }

    if (request.method == 'POST' &&
        _recoveryEmailEndpoints.handlesCompleteLocalEnrollment(
          request.uri.path,
        )) {
      await _recoveryEmailEndpoints.completeLocalEnrollment(request);
      return;
    }

    if (request.method == 'POST' &&
        _recoveryEmailEndpoints.handlesStartChange(request.uri.path)) {
      await _recoveryEmailEndpoints.startChange(request);
      return;
    }

    if (request.method == 'POST' &&
        _recoveryEmailEndpoints.handlesConfirmChange(request.uri.path)) {
      await _recoveryEmailEndpoints.confirmChange(request);
      return;
    }

    if (request.method == 'POST' &&
        _passwordResetEndpoints.handlesStart(request.uri.path)) {
      await _passwordResetEndpoints.start(request);
      return;
    }

    if (request.method == 'POST' &&
        _passwordResetEndpoints.handlesComplete(request.uri.path)) {
      await _passwordResetEndpoints.complete(request);
      return;
    }

    if (request.method == 'POST' &&
        _donationEndpoints.handles(request.uri.path)) {
      await _donationEndpoints.create(request);
      return;
    }

    if (request.method == 'POST' &&
        _walletEndpoints.handlesAccount(request.uri.path)) {
      await _walletEndpoints.account(request);
      return;
    }

    if (request.method == 'GET' &&
        _walletEndpoints.handlesSession(request.uri.path)) {
      await _walletEndpoints.session(request);
      return;
    }

    if (request.method == 'POST' &&
        _walletEndpoints.handlesUsernameAvailability(request.uri.path)) {
      await _walletEndpoints.usernameAvailability(request);
      return;
    }

    if (request.method == 'POST' &&
        _walletEndpoints.handlesNonce(request.uri.path)) {
      await _walletEndpoints.nonce(request);
      return;
    }

    if (request.method == 'POST' &&
        _walletEndpoints.handlesVerify(request.uri.path)) {
      await _walletEndpoints.verify(request);
      return;
    }

    if (request.method == 'POST' &&
        _azureBlobEndpoints.handlesSignUpload(request.uri.path)) {
      await _azureBlobEndpoints.signUpload(request);
      return;
    }

    if (request.method == 'GET' &&
        _azureBlobEndpoints.handlesDownload(request.uri.path)) {
      await _azureBlobEndpoints.download(request);
      return;
    }

    if (request.method == 'POST' &&
        _userDirectoryEndpoints.handlesUpsert(request.uri.path)) {
      await _userDirectoryEndpoints.upsert(request);
      return;
    }

    if (request.method == 'POST' &&
        _userDirectoryEndpoints.handlesSearch(request.uri.path)) {
      await _userDirectoryEndpoints.search(request);
      return;
    }

    if (request.method == 'POST' &&
        _userDirectoryEndpoints.handlesUsernameAvailability(request.uri.path)) {
      await _userDirectoryEndpoints.checkUsernameAvailability(request);
      return;
    }

    if (request.method == 'POST' &&
        _userDirectoryEndpoints.handlesRegisterOidcAccount(request.uri.path)) {
      await _userDirectoryEndpoints.registerOidcAccount(request);
      return;
    }

    if (request.method == 'POST' &&
        _userDirectoryEndpoints.handlesPrepareSecureRegistration(
          request.uri.path,
        )) {
      await _userDirectoryEndpoints.prepareSecureRegistration(request);
      return;
    }

    if (request.method == 'POST' &&
        _userDirectoryEndpoints.handlesProvisionSecureLogin(request.uri.path)) {
      await _userDirectoryEndpoints.provisionSecureLogin(request);
      return;
    }

    if (request.method == 'POST' &&
        _reportEndpoints.handlesSubmit(request.uri.path)) {
      await _reportEndpoints.submit(request);
      return;
    }

    if (request.method == 'POST' &&
        _reportEndpoints.handlesList(request.uri.path)) {
      await _reportEndpoints.list(request);
      return;
    }

    if (request.method == 'POST' &&
        _reportEndpoints.handlesUpdate(request.uri.path)) {
      await _reportEndpoints.update(request);
      return;
    }

    if (request.method == 'POST' && _pushEndpoints.handles(request.uri.path)) {
      await _pushEndpoints.forward(request);
      return;
    }

    await _json(request, HttpStatus.notFound, {'error': 'Not found'});
  } on _PayloadTooLargeException catch (error) {
    await _json(request, 413, {'error': error.message});
  } on _BadRequestException catch (error) {
    await _json(request, HttpStatus.badRequest, {'error': error.message});
  } catch (e, st) {
    _logger.error('request_failed', e, st);
    await _json(request, HttpStatus.internalServerError, {
      'error': 'Internal server error',
    });
  } finally {
    stopwatch.stop();
    _logger.request(
      request: request,
      statusCode: request.response.statusCode,
      elapsed: stopwatch.elapsed,
    );
  }
}

Future<Map<String, dynamic>> _readJson(HttpRequest request) async {
  try {
    return await readBoundedJsonObject(
      request,
      declaredContentLength: request.contentLength < 0
          ? null
          : request.contentLength,
    );
  } on RequestBodyTooLargeException {
    throw const _PayloadTooLargeException('Request body is too large');
  } on JsonRequestBodyException catch (error) {
    throw _BadRequestException(error.message);
  }
}

Map<String, dynamic> _decodeJsonMap(String body) {
  if (body.trim().isEmpty) return {};
  final decoded = jsonDecode(body);
  return decoded is Map<String, dynamic> ? decoded : {};
}

Map<String, dynamic>? _asMap(Object? value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) {
    return value.map((key, value) => MapEntry(key.toString(), value));
  }
  return null;
}

List<dynamic>? _asList(Object? value) => value is List ? value : null;

Future<void> _json(
  HttpRequest request,
  int statusCode,
  Map<String, dynamic> body,
) async {
  request.response.statusCode = statusCode;
  request.response.headers.contentType = ContentType.json;
  request.response.write(jsonEncode(body));
  await request.response.close();
}

class _BadRequestException implements Exception {
  const _BadRequestException(this.message);
  final String message;
}

class _PayloadTooLargeException implements Exception {
  const _PayloadTooLargeException(this.message);
  final String message;
}
