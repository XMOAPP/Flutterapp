import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../providers/matrix_provider.dart';
import '../services/wallet_service.dart';
import '../theme.dart';
import 'home_screen.dart';

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

  // ── Step 1: validate username ─────────────────────────────────────────────

  void _onContinue() {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _step = 'connect');
  }

  // ── Step 2: connect wallet ────────────────────────────────────────────────

  Future<void> _connectWallet(String walletName) async {
    setState(() {
      _isBusy = true;
      _error = null;
    });
    try {
      final address = await _wallet.connectWallet(walletName);
      setState(() {
        _connectedAddress = address;
        _step = 'sign';
      });
    } catch (e) {
      setState(() => _error = e.toString().replaceAll('Exception: ', ''));
    } finally {
      setState(() => _isBusy = false);
    }
  }

  // ── Step 3: sign message + login/register ────────────────────────────────

  Future<void> _signAndRegister() async {
    final username = _usernameCtrl.text.trim();
    setState(() {
      _isBusy = true;
      _error = null;
    });

    try {
      // Ask wallet to sign — triggers MetaMask/wallet popup
      await _wallet.signAuthMessage(username);

      // Signature verified locally (ownership proven).
      // Now login or create the Matrix account using the username.
      final provider = context.read<MatrixProvider>();
      // Use a deterministic password derived from wallet address
      final password = 'xmo_wallet_${_connectedAddress!.toLowerCase()}';
      
      // Try to login first (returning user)
      bool ok = await provider.login(username, password);
      
      // If login fails, try to register (new user)
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
      setState(() => _error = e.toString().replaceAll('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  // ── UI ────────────────────────────────────────────────────────────────────

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
              
              // ── Title ──────────────────────────────────────────────────
              Text(
                'Connect Wallet',
                style: GoogleFonts.inter(
                  color: kWhite,
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),

              const SizedBox(height: 32),

              // ── Content by step ───────────────────────────────────────
              if (_step == 'username') _buildUsernameStep(),
              if (_step == 'connect') _buildConnectStep(),
              if (_step == 'sign') _buildSignStep(),

              // ── Error ─────────────────────────────────────────────────
              if (_error != null) ...[
                const SizedBox(height: 16),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.error_outline,
                          color: Colors.redAccent, size: 14),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          _error!,
                          style: GoogleFonts.inter(
                              color: Colors.redAccent, fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  // ── Step: enter username ──────────────────────────────────────────────────

  Widget _buildUsernameStep() {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Center(
            child: Text(
              'USERNAME',
              style: GoogleFonts.inter(
                  color: kLightGrey,
                  fontSize: 9,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.8),
            ),
          ),
          const SizedBox(height: 6),
          TextFormField(
            controller: _usernameCtrl,
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9_\-]'))
            ],
            cursorColor: kWhite,
            style: GoogleFonts.inter(color: kWhite, fontSize: 14),
            decoration: InputDecoration(
              hintText: 'e.g. alice',
              hintStyle: GoogleFonts.inter(color: kLightGrey, fontSize: 14),
              filled: true,
              fillColor: kDarkGrey,
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(25),
                  borderSide: BorderSide.none),
              enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(25),
                  borderSide: BorderSide.none),
              focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(25),
                  borderSide: const BorderSide(color: kWhite, width: 1)),
              errorBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(25),
                  borderSide:
                      BorderSide(color: Colors.red.withValues(alpha: 0.6))),
              focusedErrorBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(25),
                  borderSide:
                      BorderSide(color: Colors.red.withValues(alpha: 0.6), width: 2)),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            ),
            validator: (v) {
              if (v == null || v.trim().isEmpty) return 'Username is required';
              if (v.trim().length < 3) return 'Min 3 characters';
              return null;
            },
          ),
          const SizedBox(height: 6),
          Text(
            'Only letters, numbers, _ and - allowed',
            style: GoogleFonts.inter(color: kLightGrey, fontSize: 11),
          ),
          const SizedBox(height: 24),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: SizedBox(
              width: double.infinity,
              height: 40,
              child: ElevatedButton(
                onPressed: _onContinue,
                style: ElevatedButton.styleFrom(
                  backgroundColor: kWhite,
                  foregroundColor: kBlack,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                  elevation: 0,
                ),
                child: Text(
                  'Continue',
                  style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Step: choose wallet ───────────────────────────────────────────────────

  Widget _buildConnectStep() {
    final wallets = _wallet.detectWallets();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Center(
          child: Text(
            'CHOOSE WALLET',
            style: GoogleFonts.inter(
                color: kLightGrey,
                fontSize: 9,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.8),
          ),
        ),
        const SizedBox(height: 12),
        if (_isBusy)
          const Center(
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 32),
              child: CircularProgressIndicator(color: kWhite),
            ),
          )
        else
          ...wallets.map((name) => _WalletTile(
                name: name,
                onTap: () => _connectWallet(name),
              )),
      ],
    );
  }

  // ── Step: sign message ────────────────────────────────────────────────────

  Widget _buildSignStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // Connected wallet address
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: kDarkGrey,
            borderRadius: BorderRadius.circular(25),
          ),
          child: Center(
            child: Text(
              _wallet.shortAddress(_connectedAddress ?? ''),
              style: GoogleFonts.inter(
                  color: kWhite,
                  fontSize: 14,
                  fontWeight: FontWeight.w600),
            ),
          ),
        ),
        const SizedBox(height: 12),

        // Username
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: kDarkGrey,
            borderRadius: BorderRadius.circular(25),
          ),
          child: Center(
            child: Text(
              _usernameCtrl.text.trim(),
              style: GoogleFonts.inter(
                  color: kWhite,
                  fontSize: 14,
                  fontWeight: FontWeight.w600),
            ),
          ),
        ),
        const SizedBox(height: 20),

        Text(
          'Your wallet will ask you to sign a message.\nNo transaction or gas fees required.',
          textAlign: TextAlign.center,
          style: GoogleFonts.inter(
              color: kLightGrey, fontSize: 12, height: 1.6),
        ),
        const SizedBox(height: 24),

        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 40),
          child: SizedBox(
            width: double.infinity,
            height: 40,
            child: ElevatedButton(
              onPressed: _isBusy ? null : _signAndRegister,
              style: ElevatedButton.styleFrom(
                backgroundColor: kWhite,
                foregroundColor: kBlack,
                disabledBackgroundColor: kWhite.withValues(alpha: 0.5),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                elevation: 0,
              ),
              child: _isBusy
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2.5, color: kBlack))
                  : Text(
                      'Sign & Continue',
                      style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600),
                    ),
            ),
          ),
        ),
      ],
    );
  }
}

// ── Wallet Tile ────────────────────────────────────────────────────────────

class _WalletTile extends StatelessWidget {
  final String name;
  final VoidCallback? onTap;

  const _WalletTile({
    required this.name,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        decoration: BoxDecoration(
          color: kDarkGrey,
          borderRadius: BorderRadius.circular(25),
        ),
        child: Center(
          child: Text(
            name,
            style: GoogleFonts.inter(
              color: kWhite,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}
