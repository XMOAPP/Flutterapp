import 'package:flutter/material.dart';
import 'package:xmo/utils/user_facing_error.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../providers/matrix_provider.dart';
import '../services/thirdweb_donation_service.dart';
import '../theme.dart';

class DonationScreen extends StatefulWidget {
  const DonationScreen({super.key});

  @override
  State<DonationScreen> createState() => _DonationScreenState();
}

class _DonationScreenState extends State<DonationScreen> {
  final _amountCtrl = TextEditingController(text: '5');
  final _donationService = const ThirdwebDonationService();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _amountCtrl.dispose();
    super.dispose();
  }

  Future<void> _donate() async {
    final amount = _parseUsdToUsdcSmallestUnit(_amountCtrl.text);
    if (amount == null || amount < BigInt.from(5000000)) {
      setState(() => _error = 'Minimum donation is \$5.');
      return;
    }
    final accessToken = context.read<MatrixProvider>().accessToken;
    if (accessToken == null || accessToken.isEmpty) {
      setState(() => _error = 'Sign in to donate.');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final payment = await _donationService.createDonationPayment(
        amountUsdcSmallestUnit: amount,
        accessToken: accessToken,
      );
      if (!mounted) return;
      final opened =
          await launchUrl(payment.link, mode: LaunchMode.externalApplication) ||
          await launchUrl(payment.link, mode: LaunchMode.platformDefault);
      if (!opened && mounted) {
        setState(() => _error = 'Could not open donation checkout.');
      }
    } catch (e) {
      if (!mounted) return;
      setState(
        () => _error = userFacingError(
          e,
          fallback: 'Could not start the donation. Please try again.',
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  BigInt? _parseUsdToUsdcSmallestUnit(String raw) {
    final cleaned = raw.trim().replaceAll(',', '');
    if (cleaned.isEmpty) return null;
    final match = RegExp(r'^(\d+)(?:\.(\d{0,2}))?$').firstMatch(cleaned);
    if (match == null) return null;
    final dollars = BigInt.tryParse(match.group(1) ?? '');
    if (dollars == null) return null;
    final centsText = (match.group(2) ?? '').padRight(2, '0');
    final cents = BigInt.tryParse(centsText.isEmpty ? '0' : centsText);
    if (cents == null) return null;
    return (dollars * BigInt.from(1000000)) + (cents * BigInt.from(10000));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      resizeToAvoidBottomInset: false,
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        title: Text(
          'Donation',
          style: GoogleFonts.inter(
            color: kWhite,
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset(
            'assets/images/335899110423217.5fed436687231.gif',
            fit: BoxFit.contain,
            alignment: const Alignment(0, 0.25),
          ),
          SafeArea(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(28, 24, 28, 28),
              children: [
                Text(
                  'Support XMO',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(
                    color: kWhite,
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 28),
                _sectionLabel('AMOUNT'),
                const SizedBox(height: 8),
                TextField(
                  controller: _amountCtrl,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                  ],
                  cursorColor: kWhite,
                  style: GoogleFonts.inter(
                    color: kWhite,
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                  decoration: InputDecoration(
                    prefixText: '\$ ',
                    prefixStyle: GoogleFonts.inter(
                      color: kWhite,
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                    hintText: '5.00',
                    hintStyle: GoogleFonts.inter(
                      color: kLightGrey,
                      fontSize: 18,
                    ),
                    filled: true,
                    fillColor: Colors.white.withValues(alpha: 0.14),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(24),
                      borderSide: BorderSide.none,
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(24),
                      borderSide: BorderSide.none,
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(24),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 14,
                    ),
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 18),
                  _ErrorBox(_error!),
                ],
                const SizedBox(height: 28),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 34),
                  child: SizedBox(
                    height: 48,
                    child: ElevatedButton(
                      onPressed: _busy ? null : _donate,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: kWhite,
                        foregroundColor: kBlack,
                        disabledBackgroundColor: kWhite.withValues(alpha: 0.5),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(30),
                        ),
                        elevation: 0,
                      ),
                      child: _busy
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                color: kBlack,
                                strokeWidth: 2.5,
                              ),
                            )
                          : Text(
                              'Donate',
                              style: GoogleFonts.inter(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionLabel(String text) {
    return Text(
      text,
      style: GoogleFonts.inter(
        color: kLightGrey,
        fontSize: 10,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.8,
      ),
    );
  }
}

class _ErrorBox extends StatelessWidget {
  final String message;

  const _ErrorBox(this.message);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.redAccent.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.redAccent.withValues(alpha: 0.45)),
      ),
      child: Text(
        message,
        style: GoogleFonts.inter(
          color: Colors.redAccent,
          fontSize: 12,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}
