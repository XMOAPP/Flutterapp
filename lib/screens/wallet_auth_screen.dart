import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:reown_appkit/reown_appkit.dart';

import '../config/app_config.dart';
import '../providers/matrix_provider.dart';
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
  bool _isInitializing = true;
  bool _isBusy = false;
  String? _error;
  String _step = 'username';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _initWalletKit());
  }

  @override
  void dispose() {
    _usernameCtrl.dispose();
    _appKitModal?.removeListener(_onWalletStateChanged);
    _appKitModal?.dispose();
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
          url: 'https://xmo.chat',
          icons: ['https://xmo.chat/favicon.png'],
          redirect: Redirect(
            native: 'xmo://wallet',
            universal: 'https://xmo.chat',
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
        },
      );

      WalletDeepLinkHandler.attach(appKitModal);
      appKitModal.addListener(_onWalletStateChanged);
      await appKitModal.init();
      await WalletDeepLinkHandler.checkInitialLink();

      if (!mounted) return;
      setState(() {
        _appKitModal = appKitModal;
        _isInitializing = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isInitializing = false;
        _error = e.toString().replaceAll('Exception: ', '');
      });
    }
  }

  void _onWalletStateChanged() {
    if (!mounted) return;
    final connected = _appKitModal?.isConnected ?? false;
    if (connected && _step == 'connect') {
      setState(() => _step = 'sign');
    } else {
      setState(() {});
    }
  }

  void _onContinue() {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _step = 'connect';
      _error = null;
    });
  }

  void _openWallets() {
    final appKitModal = _appKitModal;
    if (appKitModal == null) return;
    appKitModal.openModalView();
  }

  Future<void> _signAndRegister() async {
    final appKitModal = _appKitModal;
    final session = appKitModal?.session;
    final username = _usernameCtrl.text.trim();
    final address = session?.getAddress('eip155');

    if (appKitModal == null || session == null || address == null) {
      setState(() => _error = 'Connect a wallet first.');
      return;
    }

    setState(() {
      _isBusy = true;
      _error = null;
    });

    try {
      final message = _authMessage(username, address);
      final signature = await _personalSign(appKitModal, message, address);
      if (signature == null || signature.toString().isEmpty) {
        throw Exception('Wallet did not return a signature.');
      }

      if (!mounted) return;
      final provider = context.read<MatrixProvider>();
      final password = 'xmo_wallet_${address.toLowerCase()}';

      var ok = await provider.login(username, password);
      if (!ok) {
        ok = await provider.register(username, password);
      }

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
        setState(() => _error = provider.error ?? 'Authentication failed.');
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString().replaceAll('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  Future<dynamic> _personalSign(
    ReownAppKitModal appKitModal,
    String message,
    String address,
  ) {
    final chainId = appKitModal.selectedChain?.chainId ??
        appKitModal.session?.getApprovedChains(namespace: 'eip155')?.first ??
        'eip155:1';

    return appKitModal.request(
      topic: appKitModal.session!.topic,
      chainId: chainId,
      request: SessionRequestParams(
        method: 'personal_sign',
        params: [_hexMessage(message), address],
      ),
    );
  }

  String _authMessage(String username, String address) {
    final issuedAt = DateTime.now().toUtc().toIso8601String();
    return 'XMO wants you to sign in with your wallet.\n\n'
        'Username: $username\n'
        'Wallet: $address\n'
        'Issued At: $issuedAt\n\n'
        'This request will not trigger a blockchain transaction.';
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

  @override
  Widget build(BuildContext context) {
    final address = _appKitModal?.session?.getAddress('eip155');

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
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const SizedBox(height: 20),
              Text(
                'Connect Wallet',
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
                  onContinue: _onContinue,
                )
              else if (_step == 'connect')
                _NativeConnectStep(
                  isBusy: _isBusy,
                  onConnect: _openWallets,
                )
              else if (_step == 'sign')
                SignMessageStep(
                  connectedAddress: address ?? '',
                  username: _usernameCtrl.text.trim(),
                  isBusy: _isBusy,
                  onSign: _signAndRegister,
                  shortAddress: _shortAddress,
                ),
              if (_error != null) ...[
                const SizedBox(height: 16),
                WalletErrorDisplay(error: _error),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _NativeConnectStep extends StatelessWidget {
  final bool isBusy;
  final VoidCallback onConnect;

  const _NativeConnectStep({
    required this.isBusy,
    required this.onConnect,
  });

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
          'Select MetaMask, Rainbow, Coinbase, or another WalletConnect wallet installed on this phone.',
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
