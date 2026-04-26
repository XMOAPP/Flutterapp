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

class _WalletAuthScreenState extends State<WalletAuthScreen>
    with SingleTickerProviderStateMixin {
  final _usernameCtrl = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  final _wallet = WalletService();

  String? _connectedAddress;
  bool _isBusy = false;
  String? _error;
  String _step = 'username'; // username → connect → sign → done

  late AnimationController _pulseCtrl;
  late Animation<double> _pulseAnim;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
        vsync: this, duration: const Duration(seconds: 2))
      ..repeat(reverse: true);
    _pulseAnim = Tween(begin: 0.5, end: 1.0).animate(
        CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _usernameCtrl.dispose();
    _pulseCtrl.dispose();
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
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Header ──────────────────────────────────────────────────
              Center(
                child: Column(
                  children: [
                    AnimatedBuilder(
                      animation: _pulseAnim,
                      builder: (_, child) => Opacity(
                        opacity: _pulseAnim.value,
                        child: child,
                      ),
                      child: Container(
                        width: 72,
                        height: 72,
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFF6C63FF), Color(0xFF3ECFCF)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF6C63FF).withValues(alpha: 0.4),
                              blurRadius: 20,
                              spreadRadius: 2,
                            ),
                          ],
                        ),
                        child: const Icon(Icons.account_balance_wallet_outlined,
                            color: Colors.white, size: 36),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Connect Wallet',
                      style: GoogleFonts.inter(
                        color: kWhite,
                        fontSize: 26,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _stepSubtitle(),
                      textAlign: TextAlign.center,
                      style: GoogleFonts.inter(
                          color: kLightGrey, fontSize: 13, height: 1.5),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 36),

              // ── Step indicator ────────────────────────────────────────
              _StepIndicator(step: _step),

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
                    color: Colors.red.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.error_outline,
                          color: Colors.redAccent, size: 16),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _error!,
                          style: GoogleFonts.inter(
                              color: Colors.redAccent, fontSize: 13),
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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'USERNAME',
            style: GoogleFonts.inter(
                color: kLightGrey,
                fontSize: 11,
                fontWeight: FontWeight.w600,
                letterSpacing: 1.1),
          ),
          const SizedBox(height: 8),
          TextFormField(
            controller: _usernameCtrl,
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9_\-]'))
            ],
            style: GoogleFonts.inter(color: kWhite, fontSize: 14),
            decoration: InputDecoration(
              hintText: 'e.g. alice',
              hintStyle: GoogleFonts.inter(color: kLightGrey, fontSize: 14),
              prefixIcon:
                  const Icon(Icons.person_outline, color: kLightGrey, size: 20),
              filled: true,
              fillColor: kDarkGrey,
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none),
              enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(
                      color: Colors.white.withValues(alpha: 0.06))),
              focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: kLimeGreen, width: 1.5)),
              errorBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide:
                      BorderSide(color: Colors.red.withValues(alpha: 0.6))),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
            ),
            validator: (v) {
              if (v == null || v.trim().isEmpty) return 'Username is required';
              if (v.trim().length < 3) return 'Min 3 characters';
              return null;
            },
          ),
          const SizedBox(height: 8),
          Text(
            'Only letters, numbers, _ and - allowed',
            style: GoogleFonts.inter(color: kLightGrey, fontSize: 11),
          ),
          const SizedBox(height: 32),
          _primaryButton(
            label: 'Continue',
            onTap: _onContinue,
            gradient: const LinearGradient(
              colors: [Color(0xFF6C63FF), Color(0xFF3ECFCF)],
            ),
          ),
        ],
      ),
    );
  }

  // ── Step: choose wallet ───────────────────────────────────────────────────

  Widget _buildConnectStep() {
    final wallets = _wallet.detectWallets();

    final walletIcons = {
      'MetaMask': '🦊',
      'Brave Wallet': '🦁',
      'Coinbase Wallet': '🔵',
      'Browser Wallet': '🌐',
      'WalletConnect': '🔗',
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'USERNAME: ${_usernameCtrl.text.trim()}',
          style: GoogleFonts.inter(
            color: kLimeGreen,
            fontSize: 12,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 20),
        Text(
          'CHOOSE WALLET',
          style: GoogleFonts.inter(
              color: kLightGrey,
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.1),
        ),
        const SizedBox(height: 12),
        if (_isBusy)
          const Center(
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 32),
              child:
                  CircularProgressIndicator(color: Color(0xFF6C63FF)),
            ),
          )
        else
          ...wallets.map((name) => _WalletTile(
                icon: walletIcons[name] ?? '💼',
                name: name,
                onTap: () => _connectWallet(name),
              )),

      ],
    );
  }

  // ── Step: sign message ────────────────────────────────────────────────────

  Widget _buildSignStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Connected badge
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF0D1F2D),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
                color: const Color(0xFF6C63FF).withValues(alpha: 0.4)),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                      colors: [Color(0xFF6C63FF), Color(0xFF3ECFCF)]),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.wallet, color: Colors.white, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Wallet connected',
                      style: GoogleFonts.inter(
                          color: kWhite,
                          fontSize: 13,
                          fontWeight: FontWeight.w600),
                    ),
                    Text(
                      _wallet.shortAddress(_connectedAddress ?? ''),
                      style: GoogleFonts.inter(
                          color: kLightGrey, fontSize: 12),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                      color: Colors.green.withValues(alpha: 0.3)),
                ),
                child: Text(
                  '● Connected',
                  style: GoogleFonts.inter(
                      color: Colors.greenAccent, fontSize: 10),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),

        // Username badge
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: kDarkGrey,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
                color: kLimeGreen.withValues(alpha: 0.3)),
          ),
          child: Row(
            children: [
              const Icon(Icons.person_outline, color: kLimeGreen, size: 18),
              const SizedBox(width: 10),
              Text(
                'Username: ',
                style: GoogleFonts.inter(color: kLightGrey, fontSize: 13),
              ),
              Text(
                _usernameCtrl.text.trim(),
                style: GoogleFonts.inter(
                    color: kLimeGreen,
                    fontSize: 13,
                    fontWeight: FontWeight.w700),
              ),
            ],
          ),
        ),
        const SizedBox(height: 28),

        Text(
          'Your wallet will ask you to sign a message to confirm ownership. '
          'No transaction or gas fees required.',
          style: GoogleFonts.inter(
              color: kLightGrey, fontSize: 12.5, height: 1.6),
        ),
        const SizedBox(height: 28),

        _primaryButton(
          label: _isBusy ? '' : 'Sign & Continue',
          isLoading: _isBusy,
          onTap: _isBusy ? null : _signAndRegister,
          gradient: const LinearGradient(
            colors: [Color(0xFF6C63FF), Color(0xFF3ECFCF)],
          ),
        ),
        const SizedBox(height: 16),
        Center(
          child: GestureDetector(
            onTap: () => setState(() {
              _step = 'connect';
              _connectedAddress = null;
              _wallet.disconnect();
            }),
            child: Text(
              'Use a different wallet',
              style: GoogleFonts.inter(
                color: kLightGrey,
                fontSize: 13,
                decoration: TextDecoration.underline,
                decorationColor: kLightGrey,
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ── Shared widgets ────────────────────────────────────────────────────────

  Widget _primaryButton({
    required String label,
    VoidCallback? onTap,
    required Gradient gradient,
    bool isLoading = false,
  }) {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          decoration: BoxDecoration(
            gradient: onTap == null
                ? LinearGradient(colors: [
                    Colors.grey.withValues(alpha: 0.3),
                    Colors.grey.withValues(alpha: 0.3)
                  ])
                : gradient,
            borderRadius: BorderRadius.circular(14),
            boxShadow: onTap == null
                ? []
                : [
                    BoxShadow(
                      color: const Color(0xFF6C63FF).withValues(alpha: 0.3),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    )
                  ],
          ),
          child: Center(
            child: isLoading
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                        strokeWidth: 2.5, color: Colors.white))
                : Text(
                    label,
                    style: GoogleFonts.inter(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
          ),
        ),
      ),
    );
  }

  String _stepSubtitle() {
    switch (_step) {
      case 'username':
        return 'Choose your username first.\nThen connect any crypto wallet.';
      case 'connect':
        return 'Select your wallet to connect.\nNo private keys are ever shared.';
      case 'sign':
        return 'Sign a message to prove\nyou own this wallet address.';
      default:
        return '';
    }
  }
}

// ── Step Indicator ─────────────────────────────────────────────────────────

class _StepIndicator extends StatelessWidget {
  final String step;
  const _StepIndicator({required this.step});

  static const _steps = ['username', 'connect', 'sign'];
  static const _labels = ['Username', 'Connect', 'Sign'];

  @override
  Widget build(BuildContext context) {
    final current = _steps.indexOf(step);
    return Row(
      children: List.generate(_steps.length * 2 - 1, (i) {
        if (i.isOdd) {
          final idx = i ~/ 2;
          return Expanded(
            child: Container(
              height: 2,
              color: idx < current
                  ? const Color(0xFF6C63FF)
                  : Colors.white.withValues(alpha: 0.1),
            ),
          );
        }
        final idx = i ~/ 2;
        final done = idx < current;
        final active = idx == current;
        return Column(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: active || done
                    ? const LinearGradient(
                        colors: [Color(0xFF6C63FF), Color(0xFF3ECFCF)])
                    : null,
                color: active || done ? null : kDarkGrey,
                border: Border.all(
                  color: active
                      ? Colors.transparent
                      : Colors.white.withValues(alpha: 0.1),
                ),
              ),
              child: Center(
                child: done
                    ? const Icon(Icons.check, color: Colors.white, size: 14)
                    : Text(
                        '${idx + 1}',
                        style: GoogleFonts.inter(
                          color: active ? Colors.white : kLightGrey,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              _labels[idx],
              style: GoogleFonts.inter(
                color: active ? kWhite : kLightGrey,
                fontSize: 10,
                fontWeight:
                    active ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ],
        );
      }),
    );
  }
}

// ── Wallet Tile ────────────────────────────────────────────────────────────

class _WalletTile extends StatelessWidget {
  final String icon;
  final String name;
  final VoidCallback? onTap;

  const _WalletTile({
    required this.icon,
    required this.name,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: kDarkGrey,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.08),
          ),
        ),
        child: Row(
          children: [
            Text(icon, style: const TextStyle(fontSize: 28)),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                name,
                style: GoogleFonts.inter(
                  color: kWhite,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const Icon(Icons.arrow_forward_ios, color: kLightGrey, size: 14),
          ],
        ),
      ),
    );
  }
}
