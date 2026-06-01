import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:matrix/matrix.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:typed_data';
import '../../theme.dart';
import '../../services/channel_service.dart';
import '../../services/matrix_service.dart';
import '../../providers/matrix_provider.dart';
import '../../widgets/story/story_avatar.dart';
import 'package:provider/provider.dart';

/// Channel Settings Screen - Edit channel name, description, avatar, and settings (Admin only)
class ChannelSettingsScreen extends StatefulWidget {
  final Room room;

  const ChannelSettingsScreen({super.key, required this.room});

  @override
  State<ChannelSettingsScreen> createState() => _ChannelSettingsScreenState();
}

class _ChannelSettingsScreenState extends State<ChannelSettingsScreen> {
  final _nameCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  bool _loading = false;
  bool _isPublic = false;
  bool _signMessages = true;
  Uint8List? _selectedAvatarBytes;
  String? _selectedAvatarName;
  String? _avatarUrl;
  bool _removeAvatar = false;
  late ChannelService _channelService;

  String get _resolvedRoomName =>
      MatrixService().getResolvedDisplayName(widget.room);

  @override
  void initState() {
    super.initState();
    final matrixProvider = context.read<MatrixProvider>();
    _channelService = ChannelService(matrixProvider.service);
    _avatarUrl = _resolveRoomAvatarUrl();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    _nameCtrl.text = _resolvedRoomName;
    _descCtrl.text = widget.room.topic;
    _isPublic = widget.room.joinRules == JoinRules.public;

    try {
      final settings = await _channelService.getChannelSettings(widget.room.id);
      if (mounted) {
        setState(() {
          _signMessages = settings.signMessages;
          _avatarUrl = settings.avatarUrl ?? _resolveRoomAvatarUrl();
        });
      }
    } catch (e) {
      debugPrint('[ChannelSettings] Error loading settings: $e');
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickAvatar() async {
    debugPrint('[ChannelSettings] _pickAvatar called');
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        withData: true,
      );

      debugPrint('[ChannelSettings] FilePicker result: ${result != null}');

      if (result != null && result.files.isNotEmpty) {
        final file = result.files.first;
        debugPrint(
            '[ChannelSettings] File selected: ${file.name}, bytes: ${file.bytes?.length}');
        if (file.bytes != null) {
          setState(() {
            _selectedAvatarBytes = file.bytes;
            _selectedAvatarName = file.name;
            _removeAvatar = false;
          });
          debugPrint('[ChannelSettings] Avatar bytes set successfully');
        }
      } else {
        debugPrint('[ChannelSettings] No file selected');
      }
    } catch (e) {
      debugPrint('[ChannelSettings] Error picking avatar: $e');
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

  Future<void> _saveSettings() async {
    setState(() => _loading = true);
    try {
      // Update channel name
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

      // Update join rules
      final newJoinRule = _isPublic ? 'public' : 'invite';
      await widget.room.client.setRoomStateWithKey(
        widget.room.id,
        EventTypes.RoomJoinRules,
        '',
        {'join_rule': newJoinRule},
      );

      await widget.room.client.setRoomStateWithKey(
        widget.room.id,
        EventTypes.HistoryVisibility,
        '',
        {'history_visibility': 'shared'},
      );

      // Update sign messages setting
      await widget.room.client.setRoomStateWithKey(
        widget.room.id,
        'xmo.channel.settings',
        '',
        {'sign_messages': _signMessages},
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
        fallbackIcon: Icons.campaign,
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
      fallbackIcon: Icons.campaign,
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
          'Channel Settings',
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
                  Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () {
                        debugPrint('[ChannelSettings] Avatar tapped!');
                        _pickAvatar();
                      },
                      borderRadius: BorderRadius.circular(40),
                      child: Stack(
                        children: [
                          _buildAvatarPreview(),
                          Positioned(
                            bottom: 0,
                            right: 0,
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
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Tap to change avatar',
                    style: GoogleFonts.inter(
                      color: kLightGrey,
                      fontSize: 11,
                    ),
                  ),
                  if (_selectedAvatarBytes != null ||
                      _removeAvatar ||
                      _avatarUrl != null) ...[
                    const SizedBox(height: 2),
                    TextButton.icon(
                      onPressed: _loading ? null : _removeRoomAvatar,
                      icon: const Icon(
                        Icons.delete_outline,
                        color: Colors.redAccent,
                        size: 16,
                      ),
                      label: Text(
                        'Remove photo',
                        style: GoogleFonts.inter(
                          color: Colors.redAccent,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Channel Name
            Text(
              'Channel Name',
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
                hintText: 'Enter channel name',
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
                hintText: 'What is this channel about?',
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

            // Channel Settings
            Text(
              'Channel Settings',
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
                  'Public Channel',
                  style: GoogleFonts.inter(color: kWhite, fontSize: 13),
                ),
                subtitle: Text(
                  _isPublic
                      ? 'Anyone can find and join this channel'
                      : 'Only invited subscribers can join',
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

            // Sign Messages Toggle
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
                  'Sign Messages',
                  style: GoogleFonts.inter(color: kWhite, fontSize: 13),
                ),
                subtitle: Text(
                  _signMessages
                      ? 'Show admin name on posts'
                      : 'Posts appear as channel posts',
                  style: GoogleFonts.inter(
                    color: kLightGrey,
                    fontSize: 11,
                  ),
                ),
                value: _signMessages,
                activeThumbColor: kLimeGreen,
                onChanged: (value) {
                  setState(() => _signMessages = value);
                },
              ),
            ),
            const SizedBox(height: 20),

            // Info Box
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.transparent,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.info_outline, color: kLightGrey, size: 18),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'About Channels',
                          style: GoogleFonts.inter(
                            color: kWhite,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          'Channels are broadcast-only. Only admins can post messages. Subscribers can view and share posts.',
                          style: GoogleFonts.inter(
                            color: kLightGrey,
                            fontSize: 11,
                          ),
                        ),
                      ],
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
