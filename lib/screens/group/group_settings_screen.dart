import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:matrix/matrix.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:typed_data';
import 'package:provider/provider.dart';
import '../../theme.dart';
import '../../providers/matrix_provider.dart';
import '../../services/matrix_service.dart';
import '../../widgets/story/story_avatar.dart';
import '../camera_capture_screen.dart';

enum _RoomAvatarMenuAction { gallery, capture, remove }

/// Group Settings Screen - Edit group name, description, avatar, and settings
class GroupSettingsScreen extends StatefulWidget {
  final Room room;

  const GroupSettingsScreen({super.key, required this.room});

  @override
  State<GroupSettingsScreen> createState() => _GroupSettingsScreenState();
}

class _GroupSettingsScreenState extends State<GroupSettingsScreen> {
  final _nameCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  bool _loading = false;
  bool _isPublic = false;
  Uint8List? _selectedAvatarBytes;
  String? _selectedAvatarName;
  String? _avatarUrl;
  bool _removeAvatar = false;

  String get _resolvedRoomName =>
      MatrixService().getResolvedDisplayName(widget.room);

  @override
  void initState() {
    super.initState();
    _nameCtrl.text = _resolvedRoomName;
    _descCtrl.text = widget.room.topic;
    _isPublic = widget.room.joinRules == JoinRules.public;
    _avatarUrl = _resolveRoomAvatarUrl();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickAvatar() async {
    debugPrint('[GroupSettings] _pickAvatar called');
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        withData: true,
      );

      debugPrint('[GroupSettings] FilePicker result: ${result != null}');

      if (result != null && result.files.isNotEmpty) {
        final file = result.files.first;
        debugPrint(
            '[GroupSettings] File selected: ${file.name}, bytes: ${file.bytes?.length}');
        if (file.bytes != null) {
          setState(() {
            _selectedAvatarBytes = file.bytes;
            _selectedAvatarName = file.name;
            _removeAvatar = false;
          });
          debugPrint('[GroupSettings] Avatar bytes set successfully');
        }
      } else {
        debugPrint('[GroupSettings] No file selected');
      }
    } catch (e) {
      debugPrint('[GroupSettings] Error picking avatar: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to pick image: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _captureAvatar() async {
    final result = await Navigator.push<CameraCaptureResult>(
      context,
      MaterialPageRoute(
        builder: (_) => const CameraCaptureScreen(
          allowVideo: false,
          showCaption: false,
        ),
      ),
    );
    if (!mounted || result == null || result.bytes.isEmpty) return;

    if (result.type != CameraCaptureMediaType.image) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please capture a photo for the group avatar'),
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

  void _handleAvatarMenuAction(_RoomAvatarMenuAction action) {
    switch (action) {
      case _RoomAvatarMenuAction.gallery:
        _pickAvatar();
        break;
      case _RoomAvatarMenuAction.capture:
        _captureAvatar();
        break;
      case _RoomAvatarMenuAction.remove:
        _removeRoomAvatar();
        break;
    }
  }

  Future<void> _saveSettings() async {
    setState(() => _loading = true);
    try {
      // Update group name
      if (_nameCtrl.text.trim() != _resolvedRoomName) {
        await widget.room.setName(_nameCtrl.text.trim());
      }

      // Update description
      if (_descCtrl.text.trim() != widget.room.topic) {
        await widget.room.setDescription(_descCtrl.text.trim());
      }

      if (_removeAvatar) {
        await widget.room.client.setRoomStateWithKey(
          widget.room.id,
          'm.room.avatar',
          '',
          <String, dynamic>{},
        );
      } else if (_selectedAvatarBytes != null) {
        final matrixFile = MatrixFile(
          bytes: _selectedAvatarBytes!,
          name: _selectedAvatarName ?? 'avatar.jpg',
          mimeType: _imageContentTypeForName(_selectedAvatarName),
        );
        await widget.room.setAvatar(matrixFile);
      }

      // Update privacy settings (join rules)
      final newJoinRule = _isPublic ? 'public' : 'invite';
      await widget.room.client.setRoomStateWithKey(
        widget.room.id,
        EventTypes.RoomJoinRules,
        '',
        {'join_rule': newJoinRule},
      );

      // Update history visibility
      await widget.room.client.setRoomStateWithKey(
        widget.room.id,
        EventTypes.HistoryVisibility,
        '',
        {'history_visibility': 'shared'},
      );

      if (mounted) {
        context.read<MatrixProvider>().refreshRooms();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Settings saved successfully'),
            backgroundColor: kLimeGreen,
          ),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _imageContentTypeForName(String? fileName) {
    final lower = fileName?.toLowerCase() ?? '';
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.webp')) return 'image/webp';
    if (lower.endsWith('.gif')) return 'image/gif';
    return 'image/jpeg';
  }

  Widget _buildAvatarPreview() {
    if (_removeAvatar) {
      return StoryAvatar(
        userName: _resolvedRoomName,
        avatarUrl: null,
        size: 80,
        fallbackIcon: Icons.group,
      );
    }

    final selectedBytes = _selectedAvatarBytes;
    if (selectedBytes != null) {
      return ClipOval(
        child: Image.memory(
          selectedBytes,
          width: 80,
          height: 80,
          fit: BoxFit.cover,
          gaplessPlayback: true,
        ),
      );
    }

    return StoryAvatar(
      userName: _resolvedRoomName,
      avatarUrl: _avatarUrl ?? _resolveRoomAvatarUrl(),
      size: 80,
      fallbackIcon: Icons.group,
    );
  }

  String? _resolveRoomAvatarUrl() {
    final roomAvatar = widget.room.avatar?.toString();
    if (roomAvatar != null && roomAvatar.isNotEmpty) return roomAvatar;

    final avatarState = widget.room.getState('m.room.avatar');
    final stateUrl = avatarState?.content['url'];
    if (stateUrl is String && stateUrl.isNotEmpty) return stateUrl;

    final stateAvatarUrl = avatarState?.content['avatar_url'];
    if (stateAvatarUrl is String && stateAvatarUrl.isNotEmpty) {
      return stateAvatarUrl;
    }

    return null;
  }

  void _removeRoomAvatar() {
    setState(() {
      _removeAvatar = true;
      _selectedAvatarBytes = null;
      _selectedAvatarName = null;
      _avatarUrl = null;
    });
  }

  bool get _hasAvatar =>
      _selectedAvatarBytes != null || (!_removeAvatar && _avatarUrl != null);

  PopupMenuItem<_RoomAvatarMenuAction> _avatarMenuItem(
    _RoomAvatarMenuAction value,
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

  Widget _buildPermissionRow(String action, String level) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(
            child: Text(
              action,
              style: GoogleFonts.inter(
                color: kWhite,
                fontSize: 12,
              ),
            ),
          ),
          Text(
            level,
            style: GoogleFonts.inter(
              color: kLightGrey,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
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
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Group Settings',
          style: GoogleFonts.inter(
            color: kWhite,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
        actions: [
          if (_loading)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    color: kLimeGreen,
                    strokeWidth: 2,
                  ),
                ),
              ),
            )
          else
            TextButton(
              onPressed: _saveSettings,
              child: Text(
                'Save',
                style: GoogleFonts.inter(
                  color: kLimeGreen,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Avatar Section
            Center(
              child: Column(
                children: [
                  Stack(
                    children: [
                      _buildAvatarPreview(),
                      Positioned(
                        bottom: 0,
                        right: 0,
                        child: PopupMenuButton<_RoomAvatarMenuAction>(
                          onSelected: _loading ? null : _handleAvatarMenuAction,
                          color: const Color(0xFF2C2C2E),
                          elevation: 8,
                          offset: const Offset(0, 34),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          itemBuilder: (context) => [
                            _avatarMenuItem(
                              _RoomAvatarMenuAction.gallery,
                              Icons.photo_library,
                              'Gallery',
                            ),
                            _avatarMenuItem(
                              _RoomAvatarMenuAction.capture,
                              Icons.camera_alt,
                              'Capture',
                            ),
                            if (_hasAvatar)
                              _avatarMenuItem(
                                _RoomAvatarMenuAction.remove,
                                Icons.delete,
                                'Remove photo',
                                destructive: true,
                              ),
                          ],
                          child: Container(
                            padding: const EdgeInsets.all(6),
                            decoration: const BoxDecoration(
                              color: kLimeGreen,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.camera_alt,
                              color: kBlack,
                              size: 14,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Tap to change avatar',
                    style: GoogleFonts.inter(
                      color: kLightGrey,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Group Name
            Text(
              'Group Name',
              style: GoogleFonts.inter(
                color: kLightGrey,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            TextField(
              controller: _nameCtrl,
              style: const TextStyle(color: kWhite, fontSize: 13),
              decoration: InputDecoration(
                hintText: 'Enter group name',
                hintStyle: const TextStyle(color: Colors.white54, fontSize: 13),
                filled: true,
                fillColor: const Color(0xFF2C2C2E),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              ),
            ),
            const SizedBox(height: 16),

            // Description
            Text(
              'Description',
              style: GoogleFonts.inter(
                color: kLightGrey,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            TextField(
              controller: _descCtrl,
              style: const TextStyle(color: kWhite, fontSize: 13),
              maxLines: 3,
              decoration: InputDecoration(
                hintText: 'What is this group about?',
                hintStyle: const TextStyle(color: Colors.white54, fontSize: 13),
                filled: true,
                fillColor: const Color(0xFF2C2C2E),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.all(12),
              ),
            ),
            const SizedBox(height: 20),

            // Privacy Settings
            Text(
              'Privacy Settings',
              style: GoogleFonts.inter(
                color: kWhite,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),

            // Public/Private Toggle
            Container(
              decoration: BoxDecoration(
                color: Colors.transparent,
                borderRadius: BorderRadius.circular(12),
              ),
              child: SwitchListTile(
                dense: true,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                title: Text(
                  'Public Group',
                  style: GoogleFonts.inter(color: kWhite, fontSize: 13),
                ),
                subtitle: Text(
                  _isPublic
                      ? 'Anyone can find and join this group'
                      : 'Only invited members can join',
                  style: GoogleFonts.inter(
                    color: kLightGrey,
                    fontSize: 11,
                  ),
                ),
                value: _isPublic,
                activeThumbColor: kLimeGreen,
                onChanged: (value) {
                  setState(() => _isPublic = value);
                },
              ),
            ),
            const SizedBox(height: 8),
            const SizedBox(height: 20),

            // Permissions Info
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.transparent,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.admin_panel_settings_outlined,
                          color: kLimeGreen, size: 18),
                      const SizedBox(width: 8),
                      Text(
                        'Permissions',
                        style: GoogleFonts.inter(
                          color: kWhite,
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  _buildPermissionRow('Send Messages', 'All members'),
                  _buildPermissionRow('Invite Users', 'Moderators and above'),
                  _buildPermissionRow('Pin Messages', 'Moderators and above'),
                  _buildPermissionRow(
                      'Kick/Ban Members', 'Moderators and above'),
                  _buildPermissionRow(
                      'Delete Messages', 'Moderators and above'),
                  _buildPermissionRow('Edit Group Info', 'Admins only'),
                  const SizedBox(height: 6),
                  Text(
                    'Use Admin Panel to promote members and customize permissions',
                    style: GoogleFonts.inter(
                      color: kLightGrey,
                      fontSize: 10,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
