import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../theme.dart';

class InviteLinkView extends StatelessWidget {
  static const _platformChannel = MethodChannel('com.xmo.xmo/media_store');

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

  Future<void> _shareLink(BuildContext context) async {
    final link = inviteLink;
    if (link == null) return;

    try {
      await _platformChannel.invokeMethod<void>('shareText', {
        'text': 'Join $roomName on XMO: $link',
        'chooserTitle': 'Share invite link',
      });
    } on PlatformException catch (_) {
      await _copyToClipboard(context);
    } on MissingPluginException catch (_) {
      await _copyToClipboard(context);
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
              padding: const EdgeInsets.fromLTRB(18, 2, 18, 14),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 560),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _InviteHeader(
                        roomName: roomName,
                        roomType: roomType,
                        icon: icon,
                      ),
                      const SizedBox(height: 10),
                      if (inviteLink != null) ...[
                        _QrPanel(inviteLink: inviteLink!),
                        const SizedBox(height: 10),
                      ],
                      _InviteLinkField(
                        inviteLink: inviteLink,
                        onCopy: () => _copyToClipboard(context),
                        onShare: () => _shareLink(context),
                      ),
                      const SizedBox(height: 10),
                      _ManagementActions(
                        canRevoke: canRevoke,
                        onRegenerate: onRegenerate,
                        onRevoke: onRevoke,
                      ),
                    ],
                  ),
                ),
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
    return Column(
      children: [
        Container(
          width: 54,
          height: 54,
          decoration: const BoxDecoration(
            color: kLimeGreen,
            shape: BoxShape.circle,
          ),
          child: Center(child: Icon(icon, color: kBlack, size: 27)),
        ),
        const SizedBox(height: 9),
        Text(
          roomName,
          style: GoogleFonts.inter(
            color: kWhite,
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 4),
        Text(
          'Share this link to invite people to the $roomType',
          style: GoogleFonts.inter(color: kLightGrey, fontSize: 12),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

class _QrPanel extends StatelessWidget {
  final String inviteLink;

  const _QrPanel({required this.inviteLink});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 11, 14, 13),
      decoration: BoxDecoration(
        color: const Color(0xFF11171D),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Text(
            'Scan to join',
            style: GoogleFonts.inter(
              color: kWhite,
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Use your XMO app to scan this QR code.',
            style: GoogleFonts.inter(color: kLightGrey, fontSize: 11),
          ),
          const SizedBox(height: 9),
          SizedBox(
            width: 202,
            height: 202,
            child: Stack(
              children: [
                const Positioned(
                  left: 0,
                  top: 0,
                  child: _QrCorner(top: true, left: true),
                ),
                const Positioned(
                  right: 0,
                  top: 0,
                  child: _QrCorner(top: true, left: false),
                ),
                const Positioned(
                  left: 0,
                  bottom: 0,
                  child: _QrCorner(top: false, left: true),
                ),
                const Positioned(
                  right: 0,
                  bottom: 0,
                  child: _QrCorner(top: false, left: false),
                ),
                Center(
                  child: Container(
                    width: 184,
                    height: 184,
                    padding: const EdgeInsets.all(9),
                    decoration: BoxDecoration(
                      color: kWhite,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: QrImageView(
                      data: inviteLink,
                      version: QrVersions.auto,
                      backgroundColor: kWhite,
                      padding: EdgeInsets.zero,
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
}

class _QrCorner extends StatelessWidget {
  const _QrCorner({required this.top, required this.left});

  final bool top;
  final bool left;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 28,
      height: 28,
      child: Stack(
        children: [
          Positioned(
            top: top ? 0 : null,
            bottom: top ? null : 0,
            left: left ? 0 : null,
            right: left ? null : 0,
            child: Container(
              width: 28,
              height: 2,
              color: kLimeGreen,
            ),
          ),
          Positioned(
            top: top ? 0 : null,
            bottom: top ? null : 0,
            left: left ? 0 : null,
            right: left ? null : 0,
            child: Container(
              width: 2,
              height: 28,
              color: kLimeGreen,
            ),
          ),
        ],
      ),
    );
  }
}

class _InviteLinkField extends StatelessWidget {
  final String? inviteLink;
  final VoidCallback onCopy;
  final VoidCallback onShare;

  const _InviteLinkField({
    required this.inviteLink,
    required this.onCopy,
    required this.onShare,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = inviteLink != null;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF11171D),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Invite Link',
            style: GoogleFonts.inter(
              color: kWhite,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 7),
          Row(
            children: [
              Expanded(
                child: Text(
                  inviteLink ?? 'Generating...',
                  style: GoogleFonts.inter(color: kLightGrey, fontSize: 12),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.copy_outlined, size: 20),
                color: kWhite,
                disabledColor: kLightGrey,
                onPressed: enabled ? onCopy : null,
                tooltip: 'Copy link',
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: enabled ? onCopy : null,
                  icon: const Icon(Icons.copy_outlined, size: 18),
                  label: const Text('Copy Link'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: kLimeGreen,
                    foregroundColor: kBlack,
                    disabledBackgroundColor: kMediumGrey,
                    disabledForegroundColor: kLightGrey,
                    minimumSize: const Size.fromHeight(43),
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    textStyle: GoogleFonts.inter(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(11),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: enabled ? onShare : null,
                  icon: const Icon(Icons.share_outlined, size: 18),
                  label: const Text('Share Link'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: kWhite,
                    disabledForegroundColor: kLightGrey,
                    side: BorderSide(
                      color: enabled ? kLightGrey : kMediumGrey,
                    ),
                    minimumSize: const Size.fromHeight(43),
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    textStyle: GoogleFonts.inter(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(11),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
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
        color: const Color(0xFF11171D),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          ListTile(
            dense: true,
            visualDensity: const VisualDensity(vertical: -2),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 3,
            ),
            leading: const _ManagementIcon(
              icon: Icons.refresh,
              color: kWhite,
              backgroundColor: Color(0xFF20262D),
            ),
            title: Text(
              'Reset Link',
              style: GoogleFonts.inter(
                color: kWhite,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            subtitle: Text(
              'Disables the current link and creates a replacement',
              style: GoogleFonts.inter(color: kLightGrey, fontSize: 11),
            ),
            trailing: const Icon(
              Icons.chevron_right,
              color: kLightGrey,
              size: 22,
            ),
            onTap: onRegenerate,
          ),
          const Divider(
            color: Color(0xFF242B33),
            height: 1,
            indent: 14,
            endIndent: 14,
          ),
          ListTile(
            dense: true,
            visualDensity: const VisualDensity(vertical: -2),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 3,
            ),
            enabled: canRevoke && onRevoke != null,
            leading: _ManagementIcon(
              icon: Icons.link_off,
              color: canRevoke ? Colors.redAccent : kLightGrey,
              backgroundColor:
                  canRevoke ? const Color(0x263F151A) : const Color(0xFF20262D),
            ),
            title: Text(
              'Disable Link',
              style: GoogleFonts.inter(
                color: canRevoke ? Colors.redAccent : kLightGrey,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            subtitle: Text(
              canRevoke
                  ? 'People can no longer use this link'
                  : 'There is no active invite link',
              style: GoogleFonts.inter(color: kLightGrey, fontSize: 11),
            ),
            trailing: const Icon(
              Icons.chevron_right,
              color: kLightGrey,
              size: 22,
            ),
            onTap: canRevoke ? onRevoke : null,
          ),
        ],
      ),
    );
  }
}

class _ManagementIcon extends StatelessWidget {
  const _ManagementIcon({
    required this.icon,
    required this.color,
    required this.backgroundColor,
  });

  final IconData icon;
  final Color color;
  final Color backgroundColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 38,
      height: 38,
      decoration: BoxDecoration(
        color: backgroundColor,
        shape: BoxShape.circle,
      ),
      child: Icon(icon, color: color, size: 21),
    );
  }
}
