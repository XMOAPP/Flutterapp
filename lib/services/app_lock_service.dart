import 'dart:convert';
import 'dart:isolate';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';

class AppLockService extends ChangeNotifier with WidgetsBindingObserver {
  AppLockService._();

  static final AppLockService instance = AppLockService._();

  static const _storage = FlutterSecureStorage();
  static const _defaultTimeoutSeconds = 60;

  final LocalAuthentication _localAuth = LocalAuthentication();

  String? _userId;
  bool _initialized = false;
  bool _enabled = false;
  bool _biometricEnabled = false;
  bool _locked = false;
  int _timeoutSeconds = _defaultTimeoutSeconds;
  int _failedAttempts = 0;
  DateTime? _backgroundedAt;
  DateTime? _blockedUntil;

  bool get initialized => _initialized;
  bool get enabled => _enabled;
  bool get biometricEnabled => _biometricEnabled;
  bool get locked => _enabled && _locked;
  int get timeoutSeconds => _timeoutSeconds;
  DateTime? get blockedUntil => _blockedUntil;

  String get _scope =>
      base64Url.encode(utf8.encode(_userId ?? 'anonymous')).replaceAll('=', '');
  String _key(String suffix) => 'xmo_app_lock_${_scope}_$suffix';

  Future<void> configureForUser(String? userId) async {
    if (_userId == userId && _initialized) return;
    _userId = userId;
    _initialized = false;
    _enabled = false;
    _biometricEnabled = false;
    _locked = false;
    _failedAttempts = 0;
    _blockedUntil = null;

    if (userId == null || userId.isEmpty) {
      WidgetsBinding.instance.removeObserver(this);
      _initialized = true;
      notifyListeners();
      return;
    }

    final values = await Future.wait([
      _storage.read(key: _key('enabled')),
      _storage.read(key: _key('biometric')),
      _storage.read(key: _key('timeout')),
    ]);
    _enabled = values[0] == 'true';
    _biometricEnabled = values[1] == 'true';
    _timeoutSeconds = int.tryParse(values[2] ?? '') ?? _defaultTimeoutSeconds;
    _locked = _enabled;
    _initialized = true;
    WidgetsBinding.instance.removeObserver(this);
    WidgetsBinding.instance.addObserver(this);
    notifyListeners();
  }

  Future<bool> canUseBiometrics() async {
    try {
      return await _localAuth.isDeviceSupported() &&
          (await _localAuth.canCheckBiometrics);
    } catch (_) {
      return false;
    }
  }

  Future<void> enable({
    required String pin,
    required bool useBiometrics,
    required int timeoutSeconds,
  }) async {
    _validatePin(pin);
    final salt = _randomBytes(16);
    final hash = await _derivePinHash(pin, salt);
    await Future.wait([
      _storage.write(key: _key('salt'), value: base64Encode(salt)),
      _storage.write(key: _key('hash'), value: hash),
      _storage.write(key: _key('enabled'), value: 'true'),
      _storage.write(
        key: _key('biometric'),
        value: useBiometrics.toString(),
      ),
      _storage.write(
        key: _key('timeout'),
        value: timeoutSeconds.toString(),
      ),
    ]);
    _enabled = true;
    _biometricEnabled = useBiometrics;
    _timeoutSeconds = timeoutSeconds;
    _locked = false;
    _failedAttempts = 0;
    notifyListeners();
  }

  Future<bool> verifyPin(String pin) async {
    final blockedUntil = _blockedUntil;
    if (blockedUntil != null && DateTime.now().isBefore(blockedUntil)) {
      return false;
    }

    final saltText = await _storage.read(key: _key('salt'));
    final expected = await _storage.read(key: _key('hash'));
    if (saltText == null || expected == null) return false;

    final actual = await _derivePinHash(pin, base64Decode(saltText));
    if (!_constantTimeEquals(actual, expected)) {
      _failedAttempts += 1;
      if (_failedAttempts >= 5) {
        _blockedUntil = DateTime.now().add(const Duration(seconds: 30));
        _failedAttempts = 0;
      }
      notifyListeners();
      return false;
    }

    _unlock();
    return true;
  }

  Future<bool> authenticateBiometric() async {
    if (!_biometricEnabled || !await canUseBiometrics()) return false;
    try {
      final authenticated = await _localAuth.authenticate(
        localizedReason: 'Unlock XMO',
        options: const AuthenticationOptions(
          biometricOnly: true,
          stickyAuth: true,
          useErrorDialogs: true,
        ),
      );
      if (authenticated) _unlock();
      return authenticated;
    } catch (_) {
      return false;
    }
  }

  Future<void> setBiometricEnabled(bool value) async {
    if (value && !await canUseBiometrics()) {
      throw StateError('Biometric authentication is unavailable');
    }
    await _storage.write(key: _key('biometric'), value: value.toString());
    _biometricEnabled = value;
    notifyListeners();
  }

  Future<void> setTimeout(int seconds) async {
    await _storage.write(key: _key('timeout'), value: seconds.toString());
    _timeoutSeconds = seconds;
    notifyListeners();
  }

  Future<void> disable(String pin) async {
    if (!await verifyPin(pin)) {
      throw StateError('Incorrect PIN');
    }
    await Future.wait([
      _storage.delete(key: _key('enabled')),
      _storage.delete(key: _key('biometric')),
      _storage.delete(key: _key('timeout')),
      _storage.delete(key: _key('salt')),
      _storage.delete(key: _key('hash')),
    ]);
    _enabled = false;
    _locked = false;
    _biometricEnabled = false;
    notifyListeners();
  }

  void lockNow() {
    if (!_enabled) return;
    _locked = true;
    notifyListeners();
  }

  void _unlock() {
    _locked = false;
    _failedAttempts = 0;
    _blockedUntil = null;
    _backgroundedAt = null;
    notifyListeners();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_enabled) return;
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      _backgroundedAt ??= DateTime.now();
      if (_timeoutSeconds == 0) lockNow();
      return;
    }
    if (state == AppLifecycleState.resumed && _backgroundedAt != null) {
      final elapsed = DateTime.now().difference(_backgroundedAt!).inSeconds;
      if (elapsed >= _timeoutSeconds) lockNow();
      _backgroundedAt = null;
    }
  }

  void _validatePin(String pin) {
    if (!RegExp(r'^\d{4,8}$').hasMatch(pin)) {
      throw ArgumentError('PIN must contain 4 to 8 digits');
    }
  }

  static List<int> _randomBytes(int length) {
    final random = Random.secure();
    return List<int>.generate(length, (_) => random.nextInt(256));
  }

  static Future<String> _derivePinHash(String pin, List<int> salt) {
    return Isolate.run(() {
      var digest = sha256.convert([...salt, ...utf8.encode(pin)]).bytes;
      for (var i = 0; i < 60000; i++) {
        digest = sha256.convert([...digest, ...salt]).bytes;
      }
      return base64Encode(digest);
    });
  }

  static bool _constantTimeEquals(String first, String second) {
    final a = utf8.encode(first);
    final b = utf8.encode(second);
    if (a.isEmpty || b.isEmpty) return a.isEmpty && b.isEmpty;
    var difference = a.length ^ b.length;
    final length = max(a.length, b.length);
    for (var i = 0; i < length; i++) {
      difference |= a[i % a.length] ^ b[i % b.length];
    }
    return difference == 0;
  }
}
