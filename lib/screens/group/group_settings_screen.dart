import 'package:xmo/utils/user_facing_error.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:matrix/matrix.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:io';
import 'dart:typed_data';
import 'package:provider/provider.dart';
import '../../config/media_upload_policy.dart';
import '../../theme.dart';
import '../../providers/matrix_provider.dart';
import '../../services/group_service.dart';
import '../../services/matrix_service.dart';
import '../../services/room_controls_service.dart';
import '../../utils/matrix_identity.dart';
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

class _SettingsDropdown<T> extends StatelessWidget {
  final String title;
  final String subtitle;
  final T value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?> onChanged;
  final bool compact;

  const _SettingsDropdown({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.items,
    required this.onChanged,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: compact ? 2 : 4),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.inter(
                    color: kWhite,
                    fontSize: compact ? 12 : 13,
                    fontWeight: compact ? FontWeight.w500 : FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: GoogleFonts.inter(color: kLightGrey, fontSize: 11),
                ),
              ],
            ),
          ),
          const SizedBox(width: 28),
          DropdownButtonHideUnderline(
            child: SizedBox(
              width: compact ? 150 : 190,
              child: DropdownButton<T>(
                value: value,
                isExpanded: true,
                alignment: Alignment.centerRight,
                dropdownColor: const Color(0xFF2C2C2E),
                iconEnabledColor: kLightGrey,
                style: GoogleFonts.inter(
                  color: kWhite,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
                items: items,
                onChanged: onChanged,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SettingsInfoRow extends StatelessWidget {
  final String title;
  final String value;
  final String subtitle;

  const _SettingsInfoRow({
    required this.title,
    required this.value,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.inter(
                    color: kWhite,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: GoogleFonts.inter(color: kLightGrey, fontSize: 11),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Text(
            value,
            textAlign: TextAlign.right,
            style: GoogleFonts.inter(
              color: kWhite,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _GroupSettingsScreenState extends State<GroupSettingsScreen> {
  final _nameCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  bool _loading = false;
  XmoJoinMode _joinMode = XmoJoinMode.invite;
  int _slowModeSeconds = 0;
  XmoRoomPermissions _permissions = const XmoRoomPermissions();
  Uint8List? _selectedAvatarBytes;
  String? _selectedAvatarName;
  String? _avatarUrl;
  bool _removeAvatar = false;
  List<User> _joinRequests = const [];
  bool _loadingJoinRequests = false;
  final Set<String> _joinRequestActions = {};

  String get _resolvedRoomName =>
      MatrixService().getResolvedDisplayName(widget.room);

  @override
  void initState() {
    super.initState();
    _nameCtrl.text = _resolvedRoomName;
    _descCtrl.text = widget.room.topic;
    _joinMode = RoomControlsService.joinModeFor(widget.room);
    _slowModeSeconds = RoomControlsService.slowModeSecondsFor(widget.room);
    _permissions = XmoRoomPermissions.fromRoom(widget.room);
    _avatarUrl = _resolveRoomAvatarUrl();
    _loadJoinRequests();
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
        withData: false,
      );

      debugPrint('[GroupSettings] FilePicker result: ${result != null}');

      if (result != null && result.files.isNotEmpty) {
        final file = result.files.first;
        MediaUploadPolicy.validate(file.size);
        final path = file.path;
        if (path == null || path.isEmpty) {
          throw const FileSystemException('Selected image is unavailable');
        }
        final bytes = await File(path).readAsBytes();
        MediaUploadPolicy.validate(bytes.lengthInBytes);
        debugPrint(
          '[GroupSettings] File selected: ${file.name}, bytes: ${bytes.length}',
        );
        if (mounted) {
          setState(() {
            _selectedAvatarBytes = bytes;
            _selectedAvatarName = file.name;
            _removeAvatar = false;
          });
          debugPrint('[GroupSettings] Avatar bytes set successfully');
        }
      } else {
        debugPrint('[GroupSettings] No file selected');
      }
    } on MediaUploadPolicyException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error.message), backgroundColor: Colors.red),
        );
      }
    } catch (e) {
      debugPrint('[GroupSettings] Error picking avatar: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(safeUserFacingText('Failed to pick image: $e')),
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
        builder: (_) =>
            const CameraCaptureScreen(allowVideo: false, showCaption: false),
      ),
    );
    if (!mounted || result == null || result.bytes.isEmpty) return;

    try {
      MediaUploadPolicy.validate(result.bytes.lengthInBytes);
    } on MediaUploadPolicyException catch (error) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.message), backgroundColor: Colors.red),
      );
      return;
    }

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

  Future<void> _loadJoinRequests() async {
    if (!mounted) return;
    setState(() => _loadingJoinRequests = true);
    try {
      final requests = await widget.room.requestParticipants(const [
        Membership.knock,
      ]);
      if (!mounted) return;
      setState(() {
        _joinRequests = requests;
        _loadingJoinRequests = false;
      });
    } catch (e) {
      debugPrint('[GroupSettings] Error loading join requests: $e');
      if (!mounted) return;
      setState(() => _loadingJoinRequests = false);
    }
  }

  Future<void> _approveJoinRequest(User user) async {
    await _handleJoinRequestAction(
      user,
      actionLabel: 'approved',
      action: () => GroupService(
        context.read<MatrixProvider>().service,
      ).addMember(widget.room.id, user.id),
    );
  }

  Future<void> _declineJoinRequest(User user) async {
    await _handleJoinRequestAction(
      user,
      actionLabel: 'declined',
      action: () => widget.room.kick(user.id),
    );
  }

  Future<void> _handleJoinRequestAction(
    User user, {
    required String actionLabel,
    required Future<void> Function() action,
  }) async {
    if (_joinRequestActions.contains(user.id)) return;
    setState(() => _joinRequestActions.add(user.id));
    try {
      await action();
      if (!mounted) return;
      setState(() {
        _joinRequests = _joinRequests
            .where((item) => item.id != user.id)
            .toList();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${MatrixIdentity.displayName(userId: user.id, candidate: user.displayName)} $actionLabel',
          ),
          backgroundColor: kLimeGreen,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            safeUserFacingText('Failed to $actionLabel request: $e'),
          ),
          backgroundColor: Colors.redAccent,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _joinRequestActions.remove(user.id));
      }
    }
  }

  Future<void> _saveSettings() async {
    final groupService = GroupService(context.read<MatrixProvider>().service);
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
        await groupService.updateGroupAvatar(
          widget.room.id,
          removeAvatar: true,
        );
      } else if (_selectedAvatarBytes != null) {
        await groupService.updateGroupAvatar(
          widget.room.id,
          avatarBytes: _selectedAvatarBytes!,
          avatarFileName: _selectedAvatarName ?? 'avatar.jpg',
        );
      }

      final immutableJoinMode = RoomControlsService.immutableJoinModeFor(
        widget.room,
      );
      await RoomControlsService.setJoinMode(widget.room, immutableJoinMode);
      final directoryVisibilitySaved =
          await RoomControlsService.setRoomDirectoryVisibility(
            widget.room,
            immutableJoinMode,
          );
      await RoomControlsService.setSlowModeSeconds(
        widget.room,
        _slowModeSeconds,
      );
      await RoomControlsService.setPermissions(widget.room, _permissions);

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
          SnackBar(
            content: Text(
              directoryVisibilitySaved
                  ? 'Settings saved successfully'
                  : 'Settings saved. Server did not allow public directory listing.',
            ),
            backgroundColor: directoryVisibilitySaved
                ? kLimeGreen
                : Colors.orangeAccent,
          ),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(safeUserFacingText('Failed to save: $e')),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
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
              style: GoogleFonts.inter(color: kWhite, fontSize: 12),
            ),
          ),
          Text(
            level,
            style: GoogleFonts.inter(color: kLightGrey, fontSize: 11),
          ),
        ],
      ),
    );
  }

  Widget _buildJoinModeSelector() {
    return _SettingsInfoRow(
      title: 'Group type',
      value: RoomControlsService.securityTypeLabelFor(widget.room),
      subtitle: RoomControlsService.securityTypeSubtitleFor(widget.room),
    );
  }

  Widget _buildJoinRequestsSection() {
    if (_joinMode != XmoJoinMode.request && _joinRequests.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF1C1D1F),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Join requests',
                  style: GoogleFonts.inter(
                    color: kWhite,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Refresh',
                onPressed: _loadingJoinRequests ? null : _loadJoinRequests,
                icon: _loadingJoinRequests
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          color: kLimeGreen,
                          strokeWidth: 2,
                        ),
                      )
                    : const Icon(Icons.refresh, color: kLightGrey, size: 20),
              ),
            ],
          ),
          if (_joinRequests.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                _loadingJoinRequests
                    ? 'Checking for pending requests...'
                    : 'No pending join requests',
                style: GoogleFonts.inter(color: kLightGrey, fontSize: 12),
              ),
            )
          else
            ..._joinRequests.map(_buildJoinRequestTile),
        ],
      ),
    );
  }

  Widget _buildJoinRequestTile(User user) {
    final busy = _joinRequestActions.contains(user.id);
    final displayName = MatrixIdentity.displayName(
      userId: user.id,
      candidate: user.displayName,
    );
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Row(
        children: [
          StoryAvatar(
            userName: displayName,
            avatarUrl: user.avatarUrl?.toString(),
            size: 38,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                    color: kWhite,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  MatrixIdentity.usernameLabel(user.id),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(color: kLightGrey, fontSize: 11),
                ),
              ],
            ),
          ),
          if (busy)
            const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(
                color: kLimeGreen,
                strokeWidth: 2,
              ),
            )
          else ...[
            IconButton(
              tooltip: 'Decline',
              onPressed: () => _declineJoinRequest(user),
              icon: const Icon(Icons.close, color: Colors.redAccent, size: 20),
            ),
            IconButton(
              tooltip: 'Approve',
              onPressed: () => _approveJoinRequest(user),
              icon: const Icon(Icons.check, color: kLimeGreen, size: 20),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSlowModeSelector() {
    return _SettingsDropdown<int>(
      title: 'Slow mode',
      subtitle: _slowModeSeconds == 0
          ? 'Members can send without delay'
          : 'Members wait $_slowModeSeconds seconds between messages',
      value: _slowModeSeconds,
      items: const [
        DropdownMenuItem(value: 0, child: Text('Off')),
        DropdownMenuItem(value: 5, child: Text('5 seconds')),
        DropdownMenuItem(value: 10, child: Text('10 seconds')),
        DropdownMenuItem(value: 30, child: Text('30 seconds')),
        DropdownMenuItem(value: 60, child: Text('1 minute')),
        DropdownMenuItem(value: 300, child: Text('5 minutes')),
      ],
      onChanged: (value) {
        if (value == null) return;
        setState(() => _slowModeSeconds = value);
      },
    );
  }

  Widget _buildPermissionSelector(
    String title,
    int value,
    ValueChanged<int> onChanged,
  ) {
    return _SettingsDropdown<int>(
      title: title,
      subtitle: RoomControlsService.roleLabelForPower(value),
      value: value,
      compact: true,
      items: const [
        DropdownMenuItem(value: 0, child: Text('All members')),
        DropdownMenuItem(value: 50, child: Text('Moderators')),
        DropdownMenuItem(value: 75, child: Text('Admins')),
        DropdownMenuItem(value: 100, child: Text('Owner')),
      ],
      onChanged: (value) {
        if (value == null) return;
        onChanged(value);
      },
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
                    style: GoogleFonts.inter(color: kLightGrey, fontSize: 11),
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
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 12,
                ),
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

            _buildJoinModeSelector(),
            _buildJoinRequestsSection(),
            const SizedBox(height: 8),
            _buildSlowModeSelector(),
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
                      const Icon(
                        Icons.admin_panel_settings_outlined,
                        color: kLimeGreen,
                        size: 18,
                      ),
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
                  _buildPermissionSelector(
                    'Send Messages',
                    _permissions.sendMessages,
                    (value) => setState(
                      () => _permissions = XmoRoomPermissions(
                        sendMessages: value,
                        sendMedia: _permissions.sendMedia,
                        startCalls: _permissions.startCalls,
                        sendPolls: _permissions.sendPolls,
                      ),
                    ),
                  ),
                  _buildPermissionSelector(
                    'Send Media & Files',
                    _permissions.sendMedia,
                    (value) => setState(
                      () => _permissions = XmoRoomPermissions(
                        sendMessages: _permissions.sendMessages,
                        sendMedia: value,
                        startCalls: _permissions.startCalls,
                        sendPolls: _permissions.sendPolls,
                      ),
                    ),
                  ),
                  _buildPermissionSelector(
                    'Start Calls',
                    _permissions.startCalls,
                    (value) => setState(
                      () => _permissions = XmoRoomPermissions(
                        sendMessages: _permissions.sendMessages,
                        sendMedia: _permissions.sendMedia,
                        startCalls: value,
                        sendPolls: _permissions.sendPolls,
                      ),
                    ),
                  ),
                  _buildPermissionSelector(
                    'Send Polls',
                    _permissions.sendPolls,
                    (value) => setState(
                      () => _permissions = XmoRoomPermissions(
                        sendMessages: _permissions.sendMessages,
                        sendMedia: _permissions.sendMedia,
                        startCalls: _permissions.startCalls,
                        sendPolls: value,
                      ),
                    ),
                  ),
                  _buildPermissionRow('Invite Users', 'Moderators and above'),
                  _buildPermissionRow('Pin Messages', 'Moderators and above'),
                  _buildPermissionRow(
                    'Kick/Ban Members',
                    'Moderators and above',
                  ),
                  _buildPermissionRow(
                    'Delete Messages',
                    'Moderators and above',
                  ),
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
