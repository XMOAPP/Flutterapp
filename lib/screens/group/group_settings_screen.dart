import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:matrix/matrix.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:typed_data';
import '../../theme.dart';
import '../../services/matrix_service.dart';

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
  bool _historyVisible = true;
  Uint8List? _selectedAvatarBytes;
  String? _selectedAvatarName;

  String get _resolvedRoomName =>
      MatrixService().getResolvedDisplayName(widget.room);

  @override
  void initState() {
    super.initState();
    _nameCtrl.text = _resolvedRoomName;
    _descCtrl.text = widget.room.topic;
    _isPublic = widget.room.joinRules == JoinRules.public;
    
    // Get history visibility
    final historyState = widget.room.getState(EventTypes.HistoryVisibility);
    _historyVisible = historyState?.content['history_visibility'] == 'shared';
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
        debugPrint('[GroupSettings] File selected: ${file.name}, bytes: ${file.bytes?.length}');
        if (file.bytes != null) {
          setState(() {
            _selectedAvatarBytes = file.bytes;
            _selectedAvatarName = file.name;
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
      
      // Update avatar if selected
      if (_selectedAvatarBytes != null) {
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
        {'history_visibility': _historyVisible ? 'shared' : 'invited'},
      );
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Settings saved successfully'),
            backgroundColor: kLimeGreen,
          ),
        );
        Navigator.pop(context);
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
                  Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () {
                        debugPrint('[GroupSettings] Avatar tapped!');
                        _pickAvatar();
                      },
                      borderRadius: BorderRadius.circular(40),
                      child: Stack(
                        children: [
                          Container(
                            width: 80,
                            height: 80,
                            decoration: BoxDecoration(
                              color: kLimeGreen,
                              shape: BoxShape.circle,
                              image: _selectedAvatarBytes != null
                                  ? DecorationImage(
                                      image: MemoryImage(_selectedAvatarBytes!),
                                      fit: BoxFit.cover,
                                    )
                                  : null,
                            ),
                            child: _selectedAvatarBytes == null
                                ? Center(
                                    child: Text(
                                      _resolvedRoomName.isNotEmpty
                                          ? _resolvedRoomName[0].toUpperCase()
                                          : 'G',
                                      style: GoogleFonts.inter(
                                        color: kBlack,
                                        fontSize: 32,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  )
                                : null,
                          ),
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
                fillColor: kDarkerGrey,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
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
                fillColor: kDarkerGrey,
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
                color: kDarkerGrey,
                borderRadius: BorderRadius.circular(12),
              ),
              child: SwitchListTile(
                dense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
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
            
            // History Visibility Toggle
            Container(
              decoration: BoxDecoration(
                color: kDarkerGrey,
                borderRadius: BorderRadius.circular(12),
              ),
              child: SwitchListTile(
                dense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                title: Text(
                  'Message History',
                  style: GoogleFonts.inter(color: kWhite, fontSize: 13),
                ),
                subtitle: Text(
                  _historyVisible
                      ? 'New members can see message history'
                      : 'New members only see messages after joining',
                  style: GoogleFonts.inter(
                    color: kLightGrey,
                    fontSize: 11,
                  ),
                ),
                value: _historyVisible,
                activeThumbColor: kLimeGreen,
                onChanged: (value) {
                  setState(() => _historyVisible = value);
                },
              ),
            ),
            const SizedBox(height: 20),
            
            // Permissions Info
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: kDarkerGrey,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.admin_panel_settings_outlined, color: kLimeGreen, size: 18),
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
                  _buildPermissionRow('Invite Users', 'Helpers and above'),
                  _buildPermissionRow('Pin Messages', 'Helpers and above'),
                  _buildPermissionRow('Kick/Ban Members', 'Moderators and above'),
                  _buildPermissionRow('Delete Messages', 'Moderators and above'),
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
