import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../theme.dart';

class InviteLinkView extends StatelessWidget {
  final String title;
  final String roomName;
  final String roomType;
  final IconData icon;
  final String? inviteLink;
  final bool canRevoke;
  final bool loading;
  final VoidCallback onBack;
  final Future<void> Function() onRegenerate;
  final Future<void> Function()? onRevoke;

  const InviteLinkView({
    super.key,
    required this.title,
    required this.roomName,
    required this.roomType,
    required this.icon,
    required this.inviteLink,
    this.canRevoke = false,
    required this.loading,
    required this.onBack,
    required this.onRegenerate,
    this.onRevoke,
  });

  Future<void> _copyToClipboard(BuildContext context) async {
    final link = inviteLink;
    if (link == null) return;

    await Clipboard.setData(ClipboardData(text: link));
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Invite link copied to clipboard'),
          backgroundColor: kLimeGreen,
          duration: Duration(seconds: 2),
        ),
      );
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
          onPressed: onBack,
        ),
        title: Text(
          title,
          style: GoogleFonts.inter(
            color: kWhite,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator(color: kLimeGreen))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _InviteHeader(
                    roomName: roomName,
                    roomType: roomType,
                    icon: icon,
                  ),
                  const SizedBox(height: 24),
                  if (inviteLink != null) ...[
                    _QrPanel(inviteLink: inviteLink!),
                    const SizedBox(height: 16),
                    Text(
                      'Scan QR code to join',
                      style: GoogleFonts.inter(
                        color: kLightGrey,
                        fontSize: 12,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 32),
                  ],
                  _InviteLinkField(
                    inviteLink: inviteLink,
                    onCopy: () => _copyToClipboard(context),
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton.icon(
                    onPressed: inviteLink == null
                        ? null
                        : () => _copyToClipboard(context),
                    icon: const Icon(Icons.copy, size: 20),
                    label: Text(
                      'Copy Link',
                      style: GoogleFonts.inter(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: kLimeGreen,
                      foregroundColor: kBlack,
                      disabledBackgroundColor: kMediumGrey,
                      disabledForegroundColor: kLightGrey,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: inviteLink == null
                        ? null
                        : () => _copyToClipboard(context),
                    icon: const Icon(Icons.share, size: 20),
                    label: Text(
                      'Share Link',
                      style: GoogleFonts.inter(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: kLimeGreen,
                      disabledForegroundColor: kLightGrey,
                      side: const BorderSide(color: kLimeGreen),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  _ManagementActions(
                    canRevoke: canRevoke,
                    onRegenerate: onRegenerate,
                    onRevoke: onRevoke,
                  ),
                ],
              ),
            ),
    );
  }
}

class _InviteHeader extends StatelessWidget {
  final String roomName;
  final String roomType;
  final IconData icon;

  const _InviteHeader({
    required this.roomName,
    required this.roomType,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Container(
            width: 60,
            height: 60,
            decoration: const BoxDecoration(
              color: kLimeGreen,
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Icon(icon, color: kBlack, size: 30),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            roomName,
            style: GoogleFonts.inter(
              color: kWhite,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 6),
          Text(
            'Share this link to invite people to the $roomType',
            style: GoogleFonts.inter(color: kLightGrey, fontSize: 12),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _QrPanel extends StatelessWidget {
  final String inviteLink;

  const _QrPanel({required this.inviteLink});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: kWhite,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Center(
        child: QrImageView(
          data: inviteLink,
          version: QrVersions.auto,
          size: 200,
          backgroundColor: kWhite,
        ),
      ),
    );
  }
}

class _InviteLinkField extends StatelessWidget {
  final String? inviteLink;
  final VoidCallback onCopy;

  const _InviteLinkField({
    required this.inviteLink,
    required this.onCopy,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Invite Link',
          style: GoogleFonts.inter(
            color: kLightGrey,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF2C2C2E),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: kMediumGrey),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  inviteLink ?? 'Generating...',
                  style: GoogleFonts.inter(color: kLimeGreen, fontSize: 13),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.copy, color: kLimeGreen, size: 20),
                onPressed: inviteLink == null ? null : onCopy,
                tooltip: 'Copy link',
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ManagementActions extends StatelessWidget {
  final bool canRevoke;
  final Future<void> Function() onRegenerate;
  final Future<void> Function()? onRevoke;

  const _ManagementActions({
    required this.canRevoke,
    required this.onRegenerate,
    required this.onRevoke,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          ListTile(
            leading: const Icon(Icons.refresh, color: kLimeGreen),
            title: Text(
              'Regenerate Link',
              style: GoogleFonts.inter(color: kWhite, fontSize: 14),
            ),
            subtitle: Text(
              'Creates a new tracked invite record',
              style: GoogleFonts.inter(color: kLightGrey, fontSize: 11),
            ),
            onTap: onRegenerate,
          ),
          const Divider(color: kMediumGrey, height: 1),
          ListTile(
            enabled: canRevoke && onRevoke != null,
            leading: Icon(
              Icons.link_off,
              color: canRevoke ? Colors.redAccent : kLightGrey,
            ),
            title: Text(
              'Revoke Link',
              style: GoogleFonts.inter(
                color: canRevoke ? Colors.redAccent : kLightGrey,
                fontSize: 14,
              ),
            ),
            subtitle: Text(
              canRevoke
                  ? 'Marks this XMO invite record inactive'
                  : 'No active tracked invite to revoke',
              style: GoogleFonts.inter(color: kLightGrey, fontSize: 11),
            ),
            onTap: canRevoke ? onRevoke : null,
          ),
        ],
      ),
    );
  }
}
