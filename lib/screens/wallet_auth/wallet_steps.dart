import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme.dart';
import '../../utils/xmo_username.dart';

// ═══════════════════════════════════════════════════════════════════════════
// WALLET AUTH STEPS
// ═══════════════════════════════════════════════════════════════════════════

class UsernameStep extends StatelessWidget {
  final GlobalKey<FormState> formKey;
  final TextEditingController controller;
  final VoidCallback onContinue;
  final bool isBusy;
  final String buttonLabel;
  final String? footerText;
  final String? footerActionLabel;
  final VoidCallback? onFooterAction;

  const UsernameStep({
    super.key,
    required this.formKey,
    required this.controller,
    required this.onContinue,
    this.isBusy = false,
    this.buttonLabel = 'Continue',
    this.footerText,
    this.footerActionLabel,
    this.onFooterAction,
  });

  @override
  Widget build(BuildContext context) {
    return Form(
      key: formKey,
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
                letterSpacing: 0.8,
              ),
            ),
          ),
          const SizedBox(height: 6),
          TextFormField(
            controller: controller,
            autocorrect: false,
            textCapitalization: TextCapitalization.none,
            inputFormatters: xmoUsernameInputFormatters(),
            cursorColor: kWhite,
            style: GoogleFonts.inter(color: kWhite, fontSize: 14),
            decoration: InputDecoration(
              hintText: 'e.g. alice',
              hintStyle: GoogleFonts.inter(color: kLightGrey, fontSize: 14),
              filled: true,
              fillColor: const Color(0xFF2C2C2E),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(25),
                borderSide: BorderSide.none,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(25),
                borderSide: BorderSide.none,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(25),
                borderSide: const BorderSide(color: kWhite, width: 1),
              ),
              errorBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(25),
                borderSide: BorderSide(
                  color: Colors.red.withValues(alpha: 0.6),
                ),
              ),
              focusedErrorBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(25),
                borderSide: BorderSide(
                  color: Colors.red.withValues(alpha: 0.6),
                  width: 2,
                ),
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 18,
                vertical: 12,
              ),
            ),
            validator: (v) {
              if (v == null || v.trim().isEmpty) return 'Username is required';
              if (!isValidXmoUsername(v.trim())) {
                return 'Use lowercase letters and numbers only';
              }
              if (v.trim().length < 3) return 'Min 3 characters';
              return null;
            },
          ),
          const SizedBox(height: 6),
          Text(
            'Only lowercase letters and numbers allowed',
            style: GoogleFonts.inter(color: kLightGrey, fontSize: 11),
          ),
          const SizedBox(height: 24),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: SizedBox(
              width: double.infinity,
              height: 40,
              child: ElevatedButton(
                onPressed: isBusy ? null : onContinue,
                style: ElevatedButton.styleFrom(
                  backgroundColor: kWhite,
                  foregroundColor: kBlack,
                  disabledBackgroundColor: kWhite.withValues(alpha: 0.5),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(30),
                  ),
                  elevation: 0,
                ),
                child: isBusy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: kBlack,
                        ),
                      )
                    : Text(
                        buttonLabel,
                        style: GoogleFonts.inter(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
              ),
            ),
          ),
          if (footerText != null &&
              footerActionLabel != null &&
              onFooterAction != null) ...[
            const SizedBox(height: 14),
            TextButton(
              onPressed: isBusy ? null : onFooterAction,
              style: TextButton.styleFrom(
                foregroundColor: kWhite,
                disabledForegroundColor: kLightGrey,
                padding: EdgeInsets.zero,
                minimumSize: const Size(0, 32),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: RichText(
                text: TextSpan(
                  style: GoogleFonts.inter(color: kLightGrey, fontSize: 12),
                  children: [
                    TextSpan(text: '$footerText '),
                    TextSpan(
                      text: footerActionLabel!,
                      style: GoogleFonts.inter(
                        color: kWhite,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class ConnectWalletStep extends StatelessWidget {
  final List<String> wallets;
  final bool isBusy;
  final Function(String) onConnect;

  const ConnectWalletStep({
    super.key,
    required this.wallets,
    required this.isBusy,
    required this.onConnect,
  });

  @override
  Widget build(BuildContext context) {
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
              letterSpacing: 0.8,
            ),
          ),
        ),
        const SizedBox(height: 12),
        if (isBusy)
          const Center(
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 32),
              child: CircularProgressIndicator(color: kWhite),
            ),
          )
        else if (wallets.isEmpty)
          const _WalletUnavailableMessage()
        else
          ...wallets.map(
            (name) => WalletTile(name: name, onTap: () => onConnect(name)),
          ),
      ],
    );
  }
}

class _WalletUnavailableMessage extends StatelessWidget {
  const _WalletUnavailableMessage();

  @override
  Widget build(BuildContext context) {
    const message = kIsWeb
        ? 'No browser wallet found. Open XMO in a browser with MetaMask or another EIP-1193 wallet installed.'
        : 'Wallet connection is currently available only on web. Use username/password on this phone build.';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      decoration: BoxDecoration(
        color: kDarkGrey,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Text(
        message,
        textAlign: TextAlign.center,
        style: GoogleFonts.inter(color: kLightGrey, fontSize: 13, height: 1.4),
      ),
    );
  }
}

class SignMessageStep extends StatelessWidget {
  final String connectedAddress;
  final String username;
  final bool isBusy;
  final VoidCallback onSign;
  final String Function(String) shortAddress;
  final String buttonLabel;
  final bool showWalletLossWarning;

  const SignMessageStep({
    super.key,
    required this.connectedAddress,
    required this.username,
    required this.isBusy,
    required this.onSign,
    required this.shortAddress,
    this.buttonLabel = 'Sign & Continue',
    this.showWalletLossWarning = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: const Color(0xFF2C2C2E),
            borderRadius: BorderRadius.circular(25),
          ),
          child: Center(
            child: Text(
              shortAddress(connectedAddress),
              style: GoogleFonts.inter(
                color: kWhite,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: const Color(0xFF2C2C2E),
            borderRadius: BorderRadius.circular(25),
          ),
          child: Center(
            child: Text(
              username,
              style: GoogleFonts.inter(
                color: kWhite,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
        const SizedBox(height: 20),
        Text(
          'Your wallet will ask you to sign a message.\nNo transaction or gas fees required.',
          textAlign: TextAlign.center,
          style: GoogleFonts.inter(
            color: kLightGrey,
            fontSize: 12,
            height: 1.6,
          ),
        ),
        if (showWalletLossWarning) ...[
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.red.withValues(alpha: 0.12),
              border: Border.all(color: Colors.red.withValues(alpha: 0.45)),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.warning_amber_rounded, color: Colors.red),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'This wallet is your account key. If you lose access to it, XMO cannot recover this wallet-only account.',
                    style: GoogleFonts.inter(
                      color: kWhite,
                      fontSize: 12,
                      height: 1.45,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 24),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 40),
          child: SizedBox(
            width: double.infinity,
            height: 40,
            child: ElevatedButton(
              onPressed: isBusy ? null : onSign,
              style: ElevatedButton.styleFrom(
                backgroundColor: kWhite,
                foregroundColor: kBlack,
                disabledBackgroundColor: kWhite.withValues(alpha: 0.5),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(30),
                ),
                elevation: 0,
              ),
              child: isBusy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: kBlack,
                      ),
                    )
                  : Text(
                      buttonLabel,
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
            ),
          ),
        ),
      ],
    );
  }
}

class WalletTile extends StatelessWidget {
  final String name;
  final VoidCallback? onTap;

  const WalletTile({super.key, required this.name, this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFF2C2C2E),
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
