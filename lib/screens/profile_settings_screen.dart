import 'dart:typed_data';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../providers/matrix_provider.dart';
import '../config/media_upload_policy.dart';
import '../services/matrix_service.dart';
import '../theme.dart';
import '../widgets/story/story_avatar.dart';
import 'camera_capture_screen.dart';

enum _AvatarMenuAction { gallery, capture, remove }

class ProfileSettingsScreen extends StatefulWidget {
  const ProfileSettingsScreen({super.key});

  @override
  State<ProfileSettingsScreen> createState() => _ProfileSettingsScreenState();
}

class _ProfileSettingsScreenState extends State<ProfileSettingsScreen> {
  final _displayNameCtrl = TextEditingController();
  Uint8List? _selectedAvatarBytes;
  String? _selectedAvatarName;
  bool _removeAvatar = false;
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

  Future<void> _pickAvatarFromGallery() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      withData: false,
    );
    if (result == null || result.files.isEmpty) return;

    final file = result.files.first;
    try {
      MediaUploadPolicy.validate(file.size);
      final path = file.path;
      if (path == null || path.isEmpty) {
        throw const FileSystemException('Selected image is unavailable');
      }
      final bytes = await File(path).readAsBytes();
      MediaUploadPolicy.validate(bytes.lengthInBytes);
      if (!mounted) return;

      setState(() {
        _selectedAvatarBytes = bytes;
        _selectedAvatarName = file.name;
        _removeAvatar = false;
      });
    } on MediaUploadPolicyException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.message), backgroundColor: kDarkGrey),
      );
    } on FileSystemException {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('The selected image is no longer available.'),
          backgroundColor: kDarkGrey,
        ),
      );
    }
  }

  Future<void> _captureAvatar() async {
    final result = await Navigator.push<CameraCaptureResult>(
      context,
      MaterialPageRoute(
        builder: (_) =>
            const CameraCaptureScreen(allowVideo: false, showCaption: false),
      ),
    );
    if (!mounted || result == null || result.bytes.isEmpty) return;

    try {
      MediaUploadPolicy.validate(result.bytes.lengthInBytes);
    } on MediaUploadPolicyException catch (error) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.message), backgroundColor: kDarkGrey),
      );
      return;
    }

    if (result.type != CameraCaptureMediaType.image) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please capture a photo for your profile'),
          backgroundColor: kDarkGrey,
        ),
      );
      return;
    }

    setState(() {
      _selectedAvatarBytes = result.bytes;
      _selectedAvatarName = result.fileName;
      _removeAvatar = false;
    });
  }

  void _handleAvatarMenuAction(_AvatarMenuAction action) {
    switch (action) {
      case _AvatarMenuAction.gallery:
        _pickAvatarFromGallery();
        break;
      case _AvatarMenuAction.capture:
        _captureAvatar();
        break;
      case _AvatarMenuAction.remove:
        _removeProfileAvatar();
        break;
    }
  }

  void _removeProfileAvatar() {
    setState(() {
      _selectedAvatarBytes = null;
      _selectedAvatarName = null;
      _removeAvatar = true;
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
    final messenger = ScaffoldMessenger.of(context);
    final update = provider.updateProfile(
      displayName: name,
      avatarBytes: _selectedAvatarBytes,
      avatarFileName: _selectedAvatarName,
      removeAvatar: _removeAvatar,
    );
    Navigator.pop(context);

    final success = await update;

    if (success) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Profile updated'),
          backgroundColor: kLimeGreen,
        ),
      );
    } else {
      messenger.showSnackBar(
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
                child: Stack(
                  children: [
                    CircleAvatar(
                      radius: 52,
                      backgroundColor: const Color(0xFF2C2C2E),
                      backgroundImage: _selectedAvatarBytes != null
                          ? MemoryImage(_selectedAvatarBytes!)
                          : null,
                      child: _selectedAvatarBytes == null
                          ? StoryAvatar(
                              userName: provider.displayName ?? '',
                              avatarUrl: _removeAvatar
                                  ? null
                                  : provider.avatarUrl,
                              size: 104,
                              backgroundColor: const Color(0xFF2C2C2E),
                              textColor: kLimeGreen,
                            )
                          : null,
                    ),
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: PopupMenuButton<_AvatarMenuAction>(
                        onSelected: _saving ? null : _handleAvatarMenuAction,
                        color: const Color(0xFF2C2C2E),
                        elevation: 8,
                        offset: const Offset(0, 38),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        itemBuilder: (context) {
                          final hasAvatar =
                              _selectedAvatarBytes != null ||
                              (!_removeAvatar && provider.avatarUrl != null);
                          return [
                            _avatarMenuItem(
                              _AvatarMenuAction.gallery,
                              Icons.photo_library,
                              'Gallery',
                            ),
                            _avatarMenuItem(
                              _AvatarMenuAction.capture,
                              Icons.camera_alt,
                              'Capture',
                            ),
                            if (hasAvatar)
                              _avatarMenuItem(
                                _AvatarMenuAction.remove,
                                Icons.delete,
                                'Remove photo',
                                destructive: true,
                              ),
                          ];
                        },
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
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Center(
                child: Text(
                  provider.userId == null
                      ? ''
                      : '@${MatrixService.cleanName(provider.userId!)}',
                  style: GoogleFonts.inter(
                    color: kLightGrey,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
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
                  fillColor: const Color(0xFF2C2C2E),
                  hintText: 'Enter display name',
                  hintStyle: GoogleFonts.inter(color: kLightGrey),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 13,
                  ),
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
                    borderSide: BorderSide(
                      color: kWhite.withValues(alpha: 0.45),
                      width: 1,
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  PopupMenuItem<_AvatarMenuAction> _avatarMenuItem(
    _AvatarMenuAction value,
    IconData icon,
    String label, {
    bool destructive = false,
  }) {
    final color = destructive ? Colors.redAccent : kWhite;
    return PopupMenuItem(
      value: value,
      height: 42,
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 12),
          Text(
            label,
            style: GoogleFonts.inter(
              color: color,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
