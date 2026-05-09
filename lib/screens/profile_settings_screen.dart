import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../providers/matrix_provider.dart';
import '../theme.dart';
import '../widgets/story/story_avatar.dart';

class ProfileSettingsScreen extends StatefulWidget {
  const ProfileSettingsScreen({super.key});

  @override
  State<ProfileSettingsScreen> createState() => _ProfileSettingsScreenState();
}

class _ProfileSettingsScreenState extends State<ProfileSettingsScreen> {
  final _displayNameCtrl = TextEditingController();
  Uint8List? _selectedAvatarBytes;
  String? _selectedAvatarName;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final provider = context.read<MatrixProvider>();
    _displayNameCtrl.text = provider.displayName ?? '';
  }

  @override
  void dispose() {
    _displayNameCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickAvatar() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;

    final file = result.files.first;
    final bytes = file.bytes;
    if (bytes == null || bytes.isEmpty) return;

    setState(() {
      _selectedAvatarBytes = bytes;
      _selectedAvatarName = file.name;
    });
  }

  Future<void> _saveProfile() async {
    final name = _displayNameCtrl.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Display name cannot be empty'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() => _saving = true);
    final provider = context.read<MatrixProvider>();
    final success = await provider.updateProfile(
      displayName: name,
      avatarBytes: _selectedAvatarBytes,
      avatarFileName: _selectedAvatarName,
    );

    if (!mounted) return;
    setState(() => _saving = false);

    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Profile updated'),
          backgroundColor: kLimeGreen,
        ),
      );
      Navigator.pop(context);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(provider.error ?? 'Failed to update profile'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<MatrixProvider>(
      builder: (context, provider, _) {
        return Scaffold(
          backgroundColor: kBlack,
          appBar: AppBar(
            title: Text(
              'My Profile',
              style: GoogleFonts.inter(
                color: kWhite,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
            actions: [
              TextButton(
                onPressed: _saving ? null : _saveProfile,
                child: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          color: kLimeGreen,
                          strokeWidth: 2,
                        ),
                      )
                    : Text(
                        'Save',
                        style: GoogleFonts.inter(
                          color: kLimeGreen,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
              ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Center(
                child: GestureDetector(
                  onTap: _pickAvatar,
                  child: Stack(
                    children: [
                      CircleAvatar(
                        radius: 52,
                        backgroundColor: kDarkerGrey,
                        backgroundImage: _selectedAvatarBytes != null
                            ? MemoryImage(_selectedAvatarBytes!)
                            : null,
                        child: _selectedAvatarBytes == null
                            ? StoryAvatar(
                                userName: provider.displayName ?? '',
                                avatarUrl: provider.avatarUrl,
                                size: 104,
                                backgroundColor: kDarkerGrey,
                                textColor: kLimeGreen,
                              )
                            : null,
                      ),
                      Positioned(
                        right: 0,
                        bottom: 0,
                        child: Container(
                          width: 34,
                          height: 34,
                          decoration: const BoxDecoration(
                            color: kLimeGreen,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.camera_alt,
                            color: kBlack,
                            size: 18,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 28),
              Text(
                'Display name',
                style: GoogleFonts.inter(
                  color: kLightGrey,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _displayNameCtrl,
                style: GoogleFonts.inter(color: kWhite, fontSize: 15),
                decoration: InputDecoration(
                  filled: true,
                  fillColor: kDarkerGrey,
                  hintText: 'Enter display name',
                  hintStyle: GoogleFonts.inter(color: kLightGrey),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: kMediumGrey),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: kMediumGrey),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: kLimeGreen),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              _buildInfoRow('User ID', provider.userId ?? ''),
            ],
          ),
        );
      },
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: kDarkerGrey,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Text(
            label,
            style: GoogleFonts.inter(color: kLightGrey, fontSize: 12),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              value,
              style: GoogleFonts.inter(color: kWhite, fontSize: 13),
              textAlign: TextAlign.right,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

}
