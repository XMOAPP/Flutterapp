import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../models/invite_link_models.dart';
import '../../theme.dart';

class InvitePreviewScreen extends StatefulWidget {
  const InvitePreviewScreen({
    super.key,
    required this.invite,
    required this.onConfirm,
  });

  final XmoInvitePreview invite;
  final Future<void> Function() onConfirm;

  @override
  State<InvitePreviewScreen> createState() => _InvitePreviewScreenState();
}

class _InvitePreviewScreenState extends State<InvitePreviewScreen> {
  bool _submitting = false;
  String? _error;

  Future<void> _confirm() async {
    if (_submitting) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await widget.onConfirm();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = error.toString().replaceFirst('InviteLinkException: ', '');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final invite = widget.invite;
    final isChannel = invite.type == 'channel';
    final action = invite.requiresApproval
        ? 'Request to join'
        : 'Join ${isChannel ? 'channel' : 'group'}';
    return Scaffold(
      backgroundColor: kBlack,
      appBar: AppBar(
        backgroundColor: kBlack,
        elevation: 0,
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.arrow_back, color: kWhite),
        ),
        title: Text(
          'XMO invite',
          style: GoogleFonts.inter(
            color: kWhite,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
          child: Column(
            children: [
              const Spacer(),
              Container(
                width: 88,
                height: 88,
                decoration: const BoxDecoration(
                  color: Color(0xFF252A2F),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  isChannel ? Icons.campaign : Icons.group,
                  color: kLimeGreen,
                  size: 42,
                ),
              ),
              const SizedBox(height: 22),
              Text(
                invite.name,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.inter(
                  color: kWhite,
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '${isChannel ? 'Channel' : 'Group'} - ${invite.memberCount} ${invite.memberCount == 1 ? 'member' : 'members'}',
                style: GoogleFonts.inter(color: kLightGrey, fontSize: 14),
              ),
              if (invite.topic?.isNotEmpty == true) ...[
                const SizedBox(height: 14),
                Text(
                  invite.topic!,
                  textAlign: TextAlign.center,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(color: kLightGrey, fontSize: 13),
                ),
              ],
              if (invite.requiresApproval) ...[
                const SizedBox(height: 14),
                Text(
                  'An admin must approve your request before you can enter.',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(color: kLightGrey, fontSize: 12),
                ),
              ],
              const Spacer(),
              if (_error != null) ...[
                Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style:
                      GoogleFonts.inter(color: Colors.redAccent, fontSize: 12),
                ),
                const SizedBox(height: 12),
              ],
              SizedBox(
                width: 360,
                height: 52,
                child: ElevatedButton(
                  onPressed: _submitting ? null : _confirm,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: kWhite,
                    foregroundColor: kBlack,
                    disabledBackgroundColor: kMediumGrey,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(26),
                    ),
                  ),
                  child: _submitting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: kBlack),
                        )
                      : Text(
                          action,
                          style: GoogleFonts.inter(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
