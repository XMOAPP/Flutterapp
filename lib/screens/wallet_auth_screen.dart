import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../providers/matrix_provider.dart';
import '../services/wallet_service.dart';
import '../theme.dart';
import 'home_screen.dart';
import 'wallet_auth/wallet_steps.dart';
import 'wallet_auth/error_display.dart';

// ═══════════════════════════════════════════════════════════════════════════
// WALLET AUTH SCREEN - Refactored
// ═══════════════════════════════════════════════════════════════════════════

class WalletAuthScreen extends StatefulWidget {
  const WalletAuthScreen({super.key});

  @override
  State<WalletAuthScreen> createState() => _WalletAuthScreenState();
}

class _WalletAuthScreenState extends State<WalletAuthScreen> {
  final _usernameCtrl = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  final _wallet = WalletService();

  String? _connectedAddress;
  bool _isBusy = false;
  String? _error;
  String _step = 'username'; // username → connect → sign → done

  @override
  void dispose() {
    _usernameCtrl.dispose();
    super.dispose();
  }

  void _onContinue() {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _step = 'connect');
  }

  Future<void> _connectWallet(String walletName) async {
    setState(() {
      _isBusy = true;
      _error = null;
    });
    try {
      final address = await _wallet.connectWallet(walletName);
      if (!mounted) return;
      setState(() {
        _connectedAddress = address;
        _step = 'sign';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString().replaceAll('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  Future<void> _signAndRegister() async {
    final username = _usernameCtrl.text.trim();
    setState(() {
      _isBusy = true;
      _error = null;
    });

    try {
      await _wallet.signAuthMessage(username);

      if (!mounted) return;
      final provider = context.read<MatrixProvider>();
      final password = 'xmo_wallet_${_connectedAddress!.toLowerCase()}';
      
      bool ok = await provider.login(username, password);
      
      if (!ok && provider.error != null && 
          (provider.error!.contains('M_FORBIDDEN') || 
           provider.error!.contains('forbidden') ||
           provider.error!.contains('Incorrect credentials'))) {
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

  @override
  Widget build(BuildContext context) {
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
              if (_step == 'username')
                UsernameStep(
                  formKey: _formKey,
                  controller: _usernameCtrl,
                  onContinue: _onContinue,
                ),
              if (_step == 'connect')
                ConnectWalletStep(
                  wallets: _wallet.detectWallets(),
                  isBusy: _isBusy,
                  onConnect: _connectWallet,
                ),
              if (_step == 'sign')
                SignMessageStep(
                  connectedAddress: _connectedAddress ?? '',
                  username: _usernameCtrl.text.trim(),
                  isBusy: _isBusy,
                  onSign: _signAndRegister,
                  shortAddress: _wallet.shortAddress,
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
