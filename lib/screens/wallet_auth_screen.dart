import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:reown_appkit/reown_appkit.dart';
import 'package:xmo/utils/user_facing_error.dart';

import '../config/app_config.dart';
import '../providers/matrix_provider.dart';
import '../services/wallet_auth_service.dart';
import '../services/wallet_deep_link_handler.dart';
import '../theme.dart';
import 'home_screen.dart';
import 'wallet_auth/error_display.dart';
import 'wallet_auth/wallet_steps.dart';

class WalletAuthScreen extends StatefulWidget {
  const WalletAuthScreen({super.key});

  @override
  State<WalletAuthScreen> createState() => _WalletAuthScreenState();
}

class _WalletAuthScreenState extends State<WalletAuthScreen> {
  final _usernameCtrl = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  ReownAppKitModal? _appKitModal;
  final _walletAuthService = const WalletAuthService();
  bool _isInitializing = true;
  bool _isBusy = false;
  bool _isResolvingWallet = false;
  bool _isNewAccount = false;
  String? _error;
  String _step = 'connect';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _initWalletKit());
  }

  @override
  void dispose() {
    _usernameCtrl.dispose();
    final appKitModal = _appKitModal;
    if (appKitModal != null) {
      WalletDeepLinkHandler.detach(appKitModal);
      appKitModal.removeListener(_onWalletStateChanged);
      appKitModal.dispose();
    }
    super.dispose();
  }

  Future<void> _initWalletKit() async {
    if (AppConfig.reownProjectId.trim().isEmpty) {
      setState(() {
        _isInitializing = false;
        _error = 'WalletConnect is not configured. Add XMO_REOWN_PROJECT_ID.';
      });
      return;
    }

    try {
      final appKitModal = ReownAppKitModal(
        context: context,
        projectId: AppConfig.reownProjectId,
        metadata: const PairingMetadata(
          name: 'XMO',
          description: 'XMO chat wallet sign-in',
          url: 'https://xmo.dpdns.org',
          icons: ['https://xmo.dpdns.org/favicon.png'],
          redirect: Redirect(
            native: 'xmo://wallet',
            universal: 'https://xmo.dpdns.org/wallet',
          ),
        ),
        featuredWalletIds: const {
          'c57ca95b47569778a828d19178114f4db188b89b763c899ba0be274e97267d96',
          '1ae92b26df02f0abca6304df07debccd18262fdf5fe82daa81593582dac9a369',
          'fd20dc426fb37566d803205b19bbc1d4096b248ac04548e3cfb6b3a38bd033aa',
        },
        optionalNamespaces: {
          'eip155': RequiredNamespace.fromJson({
            'chains': ['eip155:1', 'eip155:137', 'eip155:11155111'],
            'methods': [
              'personal_sign',
              'eth_sign',
              'eth_signTypedData',
              'eth_signTypedData_v4',
            ],
            'events': ['accountsChanged', 'chainChanged'],
          }),
          'solana': RequiredNamespace.fromJson({
            'chains': [
              'solana:5eykt4UsFv8P8NJdTREpY1vzqKqZKvdp',
              'solana:4uhcVJyU9pJkvQyS88uRDiswHXSCkY3z',
            ],
            'methods': ['solana_signMessage'],
            'events': ['accountsChanged'],
          }),
        },
      );

      appKitModal.addListener(_onWalletStateChanged);
      await appKitModal.init();
      WalletDeepLinkHandler.attach(appKitModal);
      await WalletDeepLinkHandler.checkInitialLink();

      if (!mounted) return;
      setState(() {
        _appKitModal = appKitModal;
        _isInitializing = false;
      });
      if (appKitModal.isConnected) {
        unawaited(_resolveConnectedWallet());
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isInitializing = false;
        _error = userFacingError(
          e,
          fallback: 'Wallet connection is unavailable. Please try again.',
        );
      });
    }
  }

  void _onWalletStateChanged() {
    if (!mounted) return;
    final connected = _appKitModal?.isConnected ?? false;
    if (connected) {
      unawaited(_resolveConnectedWallet());
      return;
    }
    if (_step != 'connect') {
      setState(() {
        _step = 'connect';
        _usernameCtrl.clear();
        _error = null;
      });
    }
  }

  Future<void> _resolveConnectedWallet() async {
    if (_isResolvingWallet || _isBusy) return;
    final wallet = _connectedWallet(_appKitModal);
    if (wallet == null) return;
    _isResolvingWallet = true;
    if (mounted) {
      setState(() {
        _isBusy = true;
        _error = null;
      });
    }
    try {
      final lookup = await _walletAuthService.lookupAccount(
        address: wallet.address,
        walletType: wallet.type,
      );
      if (!mounted) return;
      setState(() {
        _isNewAccount = !lookup.exists;
        _usernameCtrl.text = lookup.username;
        _step = lookup.exists ? 'sign' : 'username';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _step = 'connect';
        _error = userFacingError(
          e,
          fallback: 'Could not check this wallet. Please try again.',
        );
      });
    } finally {
      _isResolvingWallet = false;
      if (mounted) setState(() => _isBusy = false);
    }
  }

  Future<void> _onContinue() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isBusy = true;
      _error = null;
    });
    try {
      final available = await _walletAuthService.isUsernameAvailable(
        _usernameCtrl.text.trim(),
      );
      if (!mounted) return;
      if (!available) {
        setState(() {
          _error = 'Username already taken. Choose another username.';
        });
        return;
      }
      setState(() => _step = 'sign');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = _isUsernameTakenError(e)
            ? 'Username already taken. Choose another username.'
            : userFacingError(
                e,
                fallback: 'Could not check the username. Please try again.',
              );
      });
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  void _openWallets() {
    final appKitModal = _appKitModal;
    if (appKitModal == null) return;
    appKitModal.openModalView();
  }

  Future<void> _signAndContinue() async {
    final appKitModal = _appKitModal;
    final session = appKitModal?.session;
    final username = _usernameCtrl.text.trim();
    final wallet = _connectedWallet(appKitModal);

    if (appKitModal == null || session == null || wallet == null) {
      setState(() => _error = 'Connect a wallet first.');
      return;
    }

    setState(() {
      _isBusy = true;
      _error = null;
    });

    try {
      final chainId = _selectedChainId(appKitModal);
      final mode = _isNewAccount ? 'create' : 'login';
      final challenge = await _walletAuthService.createChallenge(
        username: username,
        address: wallet.address,
        mode: mode,
        walletType: wallet.type,
        chainId: chainId,
      );
      final signatureResult = await _signWalletMessage(
        appKitModal,
        wallet,
        challenge.message,
      );
      final signature = _normalizeSignature(signatureResult);
      if (signature.isEmpty) {
        throw Exception('Wallet did not return a signature.');
      }
      final verification = await _walletAuthService.verifySignature(
        username: challenge.username,
        address: wallet.address,
        mode: challenge.mode,
        walletType: wallet.type,
        message: challenge.message,
        signature: signature,
        nonce: challenge.nonce,
      );

      if (!mounted) return;
      final provider = context.read<MatrixProvider>();
      final ok = await provider.loginWithWalletToken(
        verification.matrixLoginToken,
      );

      if (!mounted) return;
      if (ok) {
        Navigator.of(context).pushAndRemoveUntil(
          PageRouteBuilder(
            pageBuilder: (_, __, ___) => const HomeScreen(),
            transitionDuration: const Duration(milliseconds: 600),
            transitionsBuilder: (_, anim, __, child) =>
                FadeTransition(opacity: anim, child: child),
          ),
          (route) => false,
        );
      } else {
        setState(() {
          _error = userFacingError(
            provider.error,
            fallback: 'Wallet login failed. Please try again.',
          );
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = _isUsernameTakenError(e)
            ? 'Username already taken. Choose another username.'
            : userFacingError(
                e,
                fallback: 'Wallet authentication failed. Please try again.',
              );
      });
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  bool _isUsernameTakenError(Object? error) {
    final raw = error?.toString().toLowerCase();
    if (raw == null) return false;
    return raw.contains('m_user_in_use') ||
        raw.contains('username already taken') ||
        raw.contains('user id already taken');
  }

  Future<dynamic> _signWalletMessage(
    ReownAppKitModal appKitModal,
    _WalletConnection wallet,
    String message,
  ) {
    if (wallet.type == 'solana') {
      return appKitModal.request(
        topic: appKitModal.session!.topic,
        chainId: wallet.chainId,
        request: SessionRequestParams(
          method: 'solana_signMessage',
          params: {'message': base58.encode(utf8.encode(message))},
        ),
      );
    }

    return appKitModal.request(
      topic: appKitModal.session!.topic,
      chainId: wallet.chainId,
      request: SessionRequestParams(
        method: 'personal_sign',
        params: [_hexMessage(message), wallet.address],
      ),
    );
  }

  String _selectedChainId(ReownAppKitModal appKitModal) {
    final wallet = _connectedWallet(appKitModal);
    if (wallet != null) return wallet.chainId;
    return 'eip155:1';
  }

  _WalletConnection? _connectedWallet(ReownAppKitModal? appKitModal) {
    final session = appKitModal?.session;
    if (session == null) return null;

    final evmAddress = session.getAddress('eip155');
    if (evmAddress != null && evmAddress.isNotEmpty) {
      final chainId =
          appKitModal?.selectedChain?.chainId ??
          session.getApprovedChains(namespace: 'eip155')?.first ??
          'eip155:1';
      return _WalletConnection(
        type: 'evm',
        address: evmAddress,
        chainId: chainId.startsWith('eip155:') ? chainId : 'eip155:$chainId',
      );
    }

    final solanaAddress = session.getAddress('solana');
    if (solanaAddress != null && solanaAddress.isNotEmpty) {
      final chainId =
          session.getApprovedChains(namespace: 'solana')?.first ??
          'solana:5eykt4UsFv8P8NJdTREpY1vzqKqZKvdp';
      return _WalletConnection(
        type: 'solana',
        address: solanaAddress,
        chainId: chainId.startsWith('solana:') ? chainId : 'solana:$chainId',
      );
    }

    return null;
  }

  String _normalizeSignature(dynamic signatureResult) {
    if (signatureResult == null) return '';
    if (signatureResult is String) return signatureResult.trim();
    if (signatureResult is List<int>) {
      return base64Encode(signatureResult);
    }
    if (signatureResult is Map) {
      final dynamic signature =
          signatureResult['signature'] ??
          signatureResult['signedMessage'] ??
          signatureResult['result'];
      return _normalizeSignature(signature);
    }
    return signatureResult.toString().trim();
  }

  String _hexMessage(String message) {
    final bytes = utf8.encode(message);
    final encoded = bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0'));
    return '0x${encoded.join()}';
  }

  String _shortAddress(String address) {
    if (address.length < 10) return address;
    return '${address.substring(0, 6)}...${address.substring(address.length - 4)}';
  }

  String get _title => _isNewAccount && _step != 'connect'
      ? 'Create Wallet Account'
      : 'Connect Wallet';

  String get _signButtonLabel =>
      _isNewAccount ? 'Sign & Create Account' : 'Sign & Login';

  @override
  Widget build(BuildContext context) {
    final address = _connectedWallet(_appKitModal)?.address;

    return Scaffold(
      backgroundColor: kBlack,
      appBar: AppBar(
        backgroundColor: kBlack,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: kWhite),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 8),
          child: SizedBox(
            width: double.infinity,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const SizedBox(height: 20),
                Text(
                  _title,
                  style: GoogleFonts.inter(
                    color: kWhite,
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 32),
                if (_isInitializing)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 32),
                    child: CircularProgressIndicator(color: kWhite),
                  )
                else if (_step == 'username')
                  UsernameStep(
                    formKey: _formKey,
                    controller: _usernameCtrl,
                    isBusy: _isBusy,
                    buttonLabel: 'Continue',
                    onContinue: _onContinue,
                  )
                else if (_step == 'connect')
                  _NativeConnectStep(isBusy: _isBusy, onConnect: _openWallets)
                else if (_step == 'sign')
                  SignMessageStep(
                    connectedAddress: address ?? '',
                    username: _usernameCtrl.text.trim(),
                    isBusy: _isBusy,
                    onSign: _signAndContinue,
                    shortAddress: _shortAddress,
                    buttonLabel: _signButtonLabel,
                    showWalletLossWarning: _isNewAccount,
                  ),
                if (_error != null) ...[
                  const SizedBox(height: 16),
                  WalletErrorDisplay(error: _error),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NativeConnectStep extends StatelessWidget {
  final bool isBusy;
  final VoidCallback onConnect;

  const _NativeConnectStep({required this.isBusy, required this.onConnect});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          'CHOOSE WALLET',
          style: GoogleFonts.inter(
            color: kLightGrey,
            fontSize: 9,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.8,
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          height: 44,
          child: ElevatedButton(
            onPressed: isBusy ? null : onConnect,
            style: ElevatedButton.styleFrom(
              backgroundColor: kWhite,
              foregroundColor: kBlack,
              disabledBackgroundColor: kWhite.withValues(alpha: 0.5),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(30),
              ),
              elevation: 0,
            ),
            child: Text(
              'Open Wallets',
              style: GoogleFonts.inter(
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
        const SizedBox(height: 14),
        Text(
          'Select MetaMask, Trust Wallet, Coinbase, Rainbow, Phantom, Solflare, or another supported WalletConnect wallet.',
          textAlign: TextAlign.center,
          style: GoogleFonts.inter(
            color: kLightGrey,
            fontSize: 12,
            height: 1.5,
          ),
        ),
      ],
    );
  }
}

class _WalletConnection {
  const _WalletConnection({
    required this.type,
    required this.address,
    required this.chainId,
  });

  final String type;
  final String address;
  final String chainId;
}
