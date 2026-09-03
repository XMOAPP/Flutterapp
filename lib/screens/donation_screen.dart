import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:xmo/utils/user_facing_error.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:reown_appkit/reown_appkit.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config/app_config.dart';
import '../providers/matrix_provider.dart';
import '../services/thirdweb_donation_service.dart';
import '../services/wallet_deep_link_handler.dart';
import '../theme.dart';

class DonationScreen extends StatefulWidget {
  const DonationScreen({super.key});

  @override
  State<DonationScreen> createState() => _DonationScreenState();
}

class _DonationScreenState extends State<DonationScreen> {
  static const _rabbyWalletId =
      '18388be9ac2d02726dbac9777c96efaac06d744b2f6d580fccdd4127a6d01fd1';
  final _amountCtrl = TextEditingController(text: '5');
  final _donationService = const ThirdwebDonationService();
  ReownAppKitModal? _walletModal;
  bool _walletInitializing = true;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _initWalletKit());
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    final walletModal = _walletModal;
    if (walletModal != null) {
      WalletDeepLinkHandler.detach(walletModal);
      walletModal.removeListener(_onWalletStateChanged);
      walletModal.dispose();
    }
    super.dispose();
  }

  Future<void> _initWalletKit() async {
    if (AppConfig.reownProjectId.trim().isEmpty) {
      if (mounted) setState(() => _walletInitializing = false);
      return;
    }

    try {
      final walletModal = ReownAppKitModal(
        context: context,
        projectId: AppConfig.reownProjectId,
        metadata: const PairingMetadata(
          name: 'XMO',
          description: 'Support XMO with a wallet donation',
          url: 'https://xmo.dpdns.org',
          icons: ['https://xmo.dpdns.org/favicon.png'],
          redirect: Redirect(
            native: 'xmo://wallet',
            universal: 'https://xmo.dpdns.org/wallet',
          ),
        ),
        featuredWalletIds: const {
          _rabbyWalletId,
          'c57ca95b47569778a828d19178114f4db188b89b763c899ba0be274e97267d96',
          '4622a2b2d6af1c9844944291e5e7351a6aa24cd7b23099efac1b2fd875da31a0',
        },
        optionalNamespaces: {
          'eip155': RequiredNamespace.fromJson({
            'chains': ['eip155:8453'],
            'methods': ['eth_sendTransaction'],
            'events': ['accountsChanged', 'chainChanged'],
          }),
        },
      );
      walletModal.addListener(_onWalletStateChanged);
      await walletModal.init();
      WalletDeepLinkHandler.attach(walletModal);
      await WalletDeepLinkHandler.checkInitialLink();
      if (!mounted) {
        walletModal.dispose();
        return;
      }
      setState(() {
        _walletModal = walletModal;
        _walletInitializing = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _walletInitializing = false;
        _error = userFacingError(
          error,
          fallback: 'Wallet connection is unavailable. Use browser checkout.',
        );
      });
    }
  }

  void _onWalletStateChanged() {
    if (mounted) setState(() {});
  }

  BigInt? _validatedAmount() {
    final amount = _parseUsdToUsdcSmallestUnit(_amountCtrl.text);
    if (amount == null || amount < BigInt.from(5000000)) {
      setState(() => _error = 'Minimum donation is \$5.');
      return null;
    }
    return amount;
  }

  String? _accessToken() {
    final accessToken = context.read<MatrixProvider>().accessToken;
    if (accessToken == null || accessToken.isEmpty) {
      setState(() => _error = 'Sign in to donate.');
      return null;
    }
    return accessToken;
  }

  Future<void> _donateWithWallet() async {
    final amount = _validatedAmount();
    if (amount == null) return;
    final accessToken = _accessToken();
    if (accessToken == null) return;

    final walletModal = _walletModal;
    if (walletModal == null || _walletInitializing) {
      setState(() => _error = 'Wallet connection is still loading.');
      return;
    }
    if (!walletModal.isConnected || walletModal.session == null) {
      setState(() => _error = null);
      await walletModal.openModalView();
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final baseNetwork = ReownAppKitModalNetworks.getNetworkInfo(
        'eip155',
        '8453',
      );
      if (baseNetwork == null) {
        throw StateError('Base network is unavailable.');
      }
      await walletModal.selectChain(baseNetwork, switchChain: true);

      final session = walletModal.session;
      final sender = session?.getAddress('eip155');
      final topic = session?.topic;
      if (session == null ||
          sender == null ||
          sender.isEmpty ||
          topic == null) {
        throw StateError('Reconnect your wallet and try again.');
      }
      final donation = await _donationService.createNativeDonationPayment(
        amountUsdcSmallestUnit: amount,
        accessToken: accessToken,
        walletAddress: sender,
      );
      String? settlementHash;
      for (final transaction in donation.transactions) {
        if (!DateTime.now().toUtc().isBefore(donation.expiresAt)) {
          throw StateError('The Thirdweb quote expired. Please try again.');
        }
        final result = await walletModal.request(
          topic: topic,
          chainId: 'eip155:${transaction.chainId}',
          request: SessionRequestParams(
            method: 'eth_sendTransaction',
            params: [
              {
                'from': sender,
                'to': transaction.to,
                'data': transaction.data,
                'value': '0x${transaction.value.toRadixString(16)}',
              },
            ],
          ),
        );
        final transactionHash = result?.toString() ?? '';
        await _recordTransactionWithRetry(
          donation: donation,
          transaction: transaction,
          transactionHash: transactionHash,
          accessToken: accessToken,
        );
        if (transaction.action != 'approval') settlementHash = transactionHash;
      }
      var status = 'submitted';
      for (var attempt = 0; attempt < 8; attempt++) {
        try {
          status = await _donationService.getNativeDonationStatus(
            donationId: donation.id,
            accessToken: accessToken,
          );
        } catch (_) {
          status = 'submitted';
          break;
        }
        if (status == 'confirmed' || status == 'failed') break;
        await Future<void>.delayed(const Duration(seconds: 2));
      }
      if (!mounted) return;
      await _showDonationStatus(status, settlementHash ?? '');
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = userFacingError(
          error,
          fallback: 'The wallet transaction could not be submitted.',
        );
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _recordTransactionWithRetry({
    required ThirdwebNativeDonation donation,
    required ThirdwebNativeTransaction transaction,
    required String transactionHash,
    required String accessToken,
  }) async {
    Object? lastError;
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        await _donationService.submitNativeTransaction(
          donationId: donation.id,
          transaction: transaction,
          transactionHash: transactionHash,
          accessToken: accessToken,
        );
        return;
      } catch (error) {
        lastError = error;
        if (attempt < 2) {
          await Future<void>.delayed(
            Duration(milliseconds: 500 * (attempt + 1)),
          );
        }
      }
    }
    throw lastError ?? StateError('Could not record the wallet transaction.');
  }

  Future<void> _openHostedCheckout() async {
    final amount = _validatedAmount();
    if (amount == null) return;

    final shouldContinue = await _confirmExternalCheckout();
    if (!shouldContinue || !mounted) return;

    final accessToken = _accessToken();
    if (accessToken == null) return;

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

  Future<void> _showDonationStatus(
    String status,
    String transactionHash,
  ) async {
    final normalizedHash =
        RegExp(r'^0x[0-9a-fA-F]{64}$').hasMatch(transactionHash)
        ? transactionHash
        : '';
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF1B1B1D),
        title: Text(
          status == 'confirmed'
              ? 'Payment completed'
              : status == 'failed'
              ? 'Payment failed'
              : 'Payment submitted',
          style: GoogleFonts.inter(color: kWhite, fontWeight: FontWeight.w700),
        ),
        content: Text(
          status == 'confirmed'
              ? 'Thirdweb verified that your donation was completed.'
              : status == 'failed'
              ? 'Thirdweb reported that the payment failed. No donation benefit was granted.'
              : normalizedHash.isEmpty
              ? 'Your wallet submitted the payment. Thirdweb is still confirming it.'
              : 'Transaction ${normalizedHash.substring(0, 10)}...${normalizedHash.substring(58)} was submitted. Thirdweb is still confirming it.',
          style: GoogleFonts.inter(color: kLightGrey, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text('Close', style: GoogleFonts.inter(color: kWhite)),
          ),
        ],
      ),
    );
  }

  Future<bool> _confirmExternalCheckout() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF1B1B1D),
        title: Text(
          'Continue in your browser?',
          style: GoogleFonts.inter(
            color: kWhite,
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
        content: Text(
          'Checkout is provided by Thirdweb and opens outside XMO. '
          'If your wallet does not open, select WalletConnect or All Wallets in checkout.',
          style: GoogleFonts.inter(
            color: kLightGrey,
            fontSize: 14,
            height: 1.4,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text('Cancel', style: GoogleFonts.inter(color: kLightGrey)),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(
              'Continue',
              style: GoogleFonts.inter(
                color: kWhite,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
    return result ?? false;
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
    final connectedWalletName = _walletModal?.session?.connectedWalletName
        ?.trim();
    final walletButtonLabel = _walletInitializing
        ? 'Preparing wallet...'
        : _walletModal == null
        ? 'Wallet unavailable'
        : connectedWalletName != null && connectedWalletName.isNotEmpty
        ? 'Donate with $connectedWalletName'
        : 'Connect wallet';

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
                Center(
                  child: SizedBox(
                    width: 250,
                    height: 48,
                    child: ElevatedButton(
                      onPressed:
                          _busy || _walletInitializing || _walletModal == null
                          ? null
                          : _donateWithWallet,
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
                              walletButtonLabel,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.inter(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Center(
                  child: SizedBox(
                    width: 250,
                    height: 42,
                    child: _LiquidGlassButton(
                      onPressed: _busy ? null : _openHostedCheckout,
                      label: 'Thirdweb browser checkout',
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

class _LiquidGlassButton extends StatelessWidget {
  const _LiquidGlassButton({required this.onPressed, required this.label});

  final VoidCallback? onPressed;
  final String label;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    const radius = BorderRadius.all(Radius.circular(21));

    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      child: Opacity(
        opacity: enabled ? 1 : 0.5,
        child: ClipRRect(
          borderRadius: radius,
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: radius,
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    kLightGrey.withValues(alpha: 0.40),
                    kLightGrey.withValues(alpha: 0.25),
                    kLightGrey.withValues(alpha: 0.16),
                  ],
                ),
                border: Border.all(color: kLightGrey.withValues(alpha: 0.55)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.28),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: onPressed,
                  borderRadius: radius,
                  splashColor: kWhite.withValues(alpha: 0.16),
                  highlightColor: kWhite.withValues(alpha: 0.08),
                  child: Center(
                    child: Text(
                      label,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(
                        color: kWhite,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
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
