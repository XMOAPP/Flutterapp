import 'dart:async';
// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:matrix/matrix.dart';
import 'package:provider/provider.dart';
import '../providers/matrix_provider.dart';
import '../models/group_models.dart';
import '../services/group_service.dart';
import '../services/privacy_service.dart';
import '../theme.dart';
import '../widgets/story/story_avatar.dart';
import 'matrix_chat_screen.dart';
import 'user_search/search_bar_widget.dart';
import 'user_search/user_tile.dart';
import 'user_search/search_states.dart';

// ═══════════════════════════════════════════════════════════════════════════
// USER SEARCH SCREEN - Refactored
// ═══════════════════════════════════════════════════════════════════════════

class UserSearchScreen extends StatefulWidget {
  const UserSearchScreen({super.key});

  @override
  State<UserSearchScreen> createState() => _UserSearchScreenState();
}

class _UserSearchScreenState extends State<UserSearchScreen> {
  final _searchCtrl = TextEditingController();
  List<Profile> _results = [];
  List<PublicRoomsChunk> _publicResults = [];
  final Map<String, bool> _publicRoomChannelFlags = {};
  final Set<String> _joiningRoomIds = {};
  bool _searching = false;
  bool _startingChat = false;
  String? _error;
  Timer? _debounce;

  @override
  void dispose() {
    _searchCtrl.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onSearchChanged(String query) {
    _debounce?.cancel();
    if (query.trim().isEmpty) {
      setState(() {
        _results = [];
        _publicResults = [];
        _publicRoomChannelFlags.clear();
        _error = null;
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 400), () {
      _performSearch(query.trim());
    });
  }

  Future<void> _performSearch(String query) async {
    if (!mounted) return;

    setState(() {
      _searching = true;
      _error = null;
    });

    final provider = context.read<MatrixProvider>();
    final myId = provider.userId;
    final publicAccounts =
        await PrivacyService(provider.service).searchPublicAccounts(query);
    final userResults = publicAccounts.map((account) {
      return Profile(
        userId: account.userId,
        displayName: account.displayName,
        avatarUrl:
            account.avatarUrl == null ? null : Uri.tryParse(account.avatarUrl!),
      );
    }).toList();
    final filteredUsers = userResults.where((p) => p.userId != myId).toList();

    var publicRooms = <PublicRoomsChunk>[];
    try {
      publicRooms = await provider.service.searchPublicRooms(query);
    } catch (e) {
      debugPrint('[NewChatSearch] Public room search failed: $e');
    }

    if (filteredUsers.isNotEmpty || publicRooms.isNotEmpty) {
      if (mounted) {
        setState(() {
          _results = filteredUsers;
          _publicResults = publicRooms;
          _searching = false;
          _error = null;
        });
        _resolvePublicRoomTypes(publicRooms);
      }
      return;
    }

    if (mounted) {
      setState(() {
        _results = [];
        _publicResults = [];
        _publicRoomChannelFlags.clear();
        _searching = false;
        _error = 'No user, group, or channel found for "$query"';
      });
    }
  }

  Future<void> _resolvePublicRoomTypes(List<PublicRoomsChunk> rooms) async {
    final provider = context.read<MatrixProvider>();
    for (final room in rooms) {
      if (_publicRoomChannelFlags.containsKey(room.roomId)) continue;
      final isChannel = await provider.service.isPublicRoomChannel(
        room.roomId,
        forceRefresh: true,
      );
      if (!mounted) return;
      setState(() => _publicRoomChannelFlags[room.roomId] = isChannel);
    }
  }

  Future<void> _startChat(Profile user) async {
    setState(() => _startingChat = true);
    final provider = context.read<MatrixProvider>();
    final roomId = await provider.startDirectChat(user.userId);

    if (!mounted) return;
    setState(() => _startingChat = false);

    if (roomId != null) {
      final room = provider.service.getRoomById(roomId);
      if (room != null) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => MatrixChatScreen(
              room: room,
              matrixProvider: provider,
            ),
          ),
        );
      }
    } else {
      setState(() => _error = provider.error ?? 'Could not start chat.');
    }
  }

  Future<Room?> _waitForCreatedRoom(
    MatrixProvider provider,
    String roomId,
  ) async {
    final delays = <Duration>[
      Duration.zero,
      const Duration(milliseconds: 250),
      const Duration(milliseconds: 500),
      const Duration(milliseconds: 900),
      const Duration(milliseconds: 1400),
    ];

    for (final delay in delays) {
      if (delay != Duration.zero) {
        await Future.delayed(delay);
      }

      final room = provider.service.getRoomById(roomId);
      if (room != null) return room;

      try {
        await provider.service.client.oneShotSync();
      } catch (e) {
        debugPrint(
            '[RoomOpen] oneShotSync failed while waiting for $roomId: $e');
      }
    }

    return provider.service.getRoomById(roomId);
  }

  Future<Room?> _waitForCreatedRoomByName(
    MatrixProvider provider,
    String roomName,
    Set<String> existingRoomIds,
  ) async {
    final matrixService = provider.service;

    final delays = <Duration>[
      Duration.zero,
      const Duration(milliseconds: 300),
      const Duration(milliseconds: 700),
      const Duration(milliseconds: 1200),
      const Duration(milliseconds: 1800),
    ];

    for (final delay in delays) {
      if (delay != Duration.zero) {
        await Future.delayed(delay);
      }

      final matches = provider.rooms.where((room) {
        if (existingRoomIds.contains(room.id)) return false;
        if (room.membership != Membership.join) return false;
        return matrixService.getResolvedDisplayName(room).trim() == roomName;
      }).toList();
      if (matches.isNotEmpty) return matches.first;

      try {
        await provider.service.client.oneShotSync();
      } catch (e) {
        debugPrint(
            '[RoomOpen] oneShotSync failed while finding "$roomName": $e');
      }
    }

    final matches = provider.rooms.where((room) {
      if (existingRoomIds.contains(room.id)) return false;
      if (room.membership != Membership.join) return false;
      return matrixService.getResolvedDisplayName(room).trim() == roomName;
    }).toList();
    return matches.isNotEmpty ? matches.first : null;
  }

  Future<void> _openCreatedRoom(MatrixProvider provider, String roomId) async {
    final room = await _waitForCreatedRoom(provider, roomId);
    provider.refreshRooms();

    if (!mounted) return;
    setState(() => _startingChat = false);

    if (room != null) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => MatrixChatScreen(
            room: room,
            matrixProvider: provider,
          ),
        ),
      );
      return;
    }

    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Created successfully. It will appear on Home shortly.'),
        backgroundColor: kLimeGreen,
      ),
    );
  }

  Future<void> _openOrJoinPublicRoom(PublicRoomsChunk publicRoom) async {
    final provider = context.read<MatrixProvider>();
    final existingRoom = provider.service.getRoomById(publicRoom.roomId);

    if (existingRoom != null) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => MatrixChatScreen(
            room: existingRoom,
            matrixProvider: provider,
          ),
        ),
      );
      return;
    }

    setState(() => _joiningRoomIds.add(publicRoom.roomId));
    try {
      await provider.service.joinRoom(publicRoom.roomId);
      await Future.delayed(const Duration(milliseconds: 600));
      await provider.service.client.oneShotSync();
      provider.refreshRooms();

      final joined = provider.service.getRoomById(publicRoom.roomId);
      if (!mounted) return;
      setState(() => _joiningRoomIds.remove(publicRoom.roomId));

      if (joined != null) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => MatrixChatScreen(
              room: joined,
              matrixProvider: provider,
            ),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _joiningRoomIds.remove(publicRoom.roomId));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to join: $e'),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  void _showCreateChannelDialog() {
    final nameCtrl = TextEditingController();
    var isPublic = true;
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: kDarkerGrey,
          title: Text('New Channel', style: GoogleFonts.inter(color: kWhite)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: nameCtrl,
                style: const TextStyle(color: kWhite),
                decoration: const InputDecoration(
                  hintText: 'Channel Name',
                  hintStyle: TextStyle(color: Colors.white54),
                  enabledBorder: UnderlineInputBorder(
                      borderSide: BorderSide(color: kLimeGreen)),
                  focusedBorder: UnderlineInputBorder(
                      borderSide: BorderSide(color: kLimeGreen)),
                ),
                autofocus: true,
              ),
              const SizedBox(height: 12),
              RadioListTile<bool>(
                value: true,
                groupValue: isPublic,
                activeColor: kLimeGreen,
                contentPadding: EdgeInsets.zero,
                title: const Text('Public', style: TextStyle(color: kWhite)),
                subtitle: const Text(
                  'Anyone can find and join this channel',
                  style: TextStyle(color: kLightGrey, fontSize: 12),
                ),
                onChanged: (value) {
                  if (value == null) return;
                  setDialogState(() => isPublic = value);
                },
              ),
              RadioListTile<bool>(
                value: false,
                groupValue: isPublic,
                activeColor: kLimeGreen,
                contentPadding: EdgeInsets.zero,
                title: const Text('Private', style: TextStyle(color: kWhite)),
                subtitle: const Text(
                  'Only invited subscribers can join',
                  style: TextStyle(color: kLightGrey, fontSize: 12),
                ),
                onChanged: (value) {
                  if (value == null) return;
                  setDialogState(() => isPublic = value);
                },
              ),
              if (isPublic)
                const Text(
                  'Public channels are not end-to-end encrypted.',
                  style: TextStyle(color: kLightGrey, fontSize: 12),
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child:
                  const Text('Cancel', style: TextStyle(color: Colors.white54)),
            ),
            TextButton(
              onPressed: () async {
                if (nameCtrl.text.trim().isEmpty) return;
                Navigator.pop(ctx);

                setState(() => _startingChat = true);
                final provider = context.read<MatrixProvider>();
                try {
                  final roomId = await provider.service.createChannel(
                    name: nameCtrl.text.trim(),
                    isPublic: isPublic,
                  );
                  await _openCreatedRoom(provider, roomId);
                } catch (e) {
                  if (!mounted) return;
                  setState(() {
                    _startingChat = false;
                    _error = 'Failed to create channel: $e';
                  });
                }
              },
              child: const Text('Create', style: TextStyle(color: kLimeGreen)),
            ),
          ],
        ),
      ),
    );
  }

  void _showCreateGroupDialog() {
    final nameCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    GroupType groupType = GroupType.private;
    JoinRule joinRule = JoinRule.invite;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: kDarkerGrey,
          title: Text('New Group', style: GoogleFonts.inter(color: kWhite)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: nameCtrl,
                  style: const TextStyle(color: kWhite),
                  decoration: const InputDecoration(
                    labelText: 'Group Name',
                    labelStyle: TextStyle(color: kLightGrey),
                    hintText: 'Enter group name',
                    hintStyle: TextStyle(color: Colors.white54),
                    enabledBorder: UnderlineInputBorder(
                        borderSide: BorderSide(color: kLimeGreen)),
                    focusedBorder: UnderlineInputBorder(
                        borderSide: BorderSide(color: kLimeGreen)),
                  ),
                  autofocus: true,
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: descCtrl,
                  style: const TextStyle(color: kWhite),
                  decoration: const InputDecoration(
                    labelText: 'Description (Optional)',
                    labelStyle: TextStyle(color: kLightGrey),
                    hintText: 'What is this group about?',
                    hintStyle: TextStyle(color: Colors.white54),
                    enabledBorder: UnderlineInputBorder(
                        borderSide: BorderSide(color: kLimeGreen)),
                    focusedBorder: UnderlineInputBorder(
                        borderSide: BorderSide(color: kLimeGreen)),
                  ),
                  maxLines: 2,
                ),
                const SizedBox(height: 20),
                Text('Group Type',
                    style: GoogleFonts.inter(color: kLightGrey, fontSize: 12)),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: RadioListTile<GroupType>(
                        title: const Text('Private (encrypted)',
                            style: TextStyle(color: kWhite, fontSize: 14)),
                        value: GroupType.private,
                        groupValue: groupType,
                        activeColor: kLimeGreen,
                        contentPadding: EdgeInsets.zero,
                        onChanged: (value) {
                          setDialogState(() => groupType = value!);
                        },
                      ),
                    ),
                    Expanded(
                      child: RadioListTile<GroupType>(
                        title: const Text('Public (not encrypted)',
                            style: TextStyle(color: kWhite, fontSize: 14)),
                        value: GroupType.public,
                        groupValue: groupType,
                        activeColor: kLimeGreen,
                        contentPadding: EdgeInsets.zero,
                        onChanged: (value) {
                          setDialogState(() => groupType = value!);
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text('Who Can Join?',
                    style: GoogleFonts.inter(color: kLightGrey, fontSize: 12)),
                const SizedBox(height: 8),
                RadioListTile<JoinRule>(
                  title: const Text('Invite Only',
                      style: TextStyle(color: kWhite, fontSize: 14)),
                  value: JoinRule.invite,
                  groupValue: joinRule,
                  activeColor: kLimeGreen,
                  contentPadding: EdgeInsets.zero,
                  onChanged: (value) {
                    setDialogState(() => joinRule = value!);
                  },
                ),
                RadioListTile<JoinRule>(
                  title: const Text('Open',
                      style: TextStyle(color: kWhite, fontSize: 14)),
                  value: JoinRule.open,
                  groupValue: joinRule,
                  activeColor: kLimeGreen,
                  contentPadding: EdgeInsets.zero,
                  onChanged: (value) {
                    setDialogState(() => joinRule = value!);
                  },
                ),
                RadioListTile<JoinRule>(
                  title: const Text('Approve Requests',
                      style: TextStyle(color: kWhite, fontSize: 14)),
                  value: JoinRule.knock,
                  groupValue: joinRule,
                  activeColor: kLimeGreen,
                  contentPadding: EdgeInsets.zero,
                  onChanged: (value) {
                    setDialogState(() => joinRule = value!);
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child:
                  const Text('Cancel', style: TextStyle(color: Colors.white54)),
            ),
            TextButton(
              onPressed: () async {
                if (nameCtrl.text.trim().isEmpty) return;
                Navigator.pop(ctx);

                setState(() => _startingChat = true);
                final matrixProvider = context.read<MatrixProvider>();
                final navigator = Navigator.of(context);
                final groupName = nameCtrl.text.trim();
                final groupDescription = descCtrl.text.trim();
                final existingRoomIds =
                    matrixProvider.rooms.map((room) => room.id).toSet();

                String? roomId;
                try {
                  debugPrint('[GroupCreation] Starting group creation...');
                  // Use GroupService directly (same pattern as channel uses MatrixService directly)
                  final groupService = GroupService(matrixProvider.service);
                  roomId = await groupService.createGroup(
                    name: groupName,
                    description:
                        groupDescription.isEmpty ? null : groupDescription,
                    type: groupType,
                    joinRule: joinRule,
                  );
                  debugPrint(
                      '[GroupCreation] Group created with roomId: $roomId');
                  await _openCreatedRoom(matrixProvider, roomId);
                } catch (e) {
                  debugPrint('[GroupCreation] Error: $e');
                  if (!mounted) return;
                  if (roomId != null) {
                    await _openCreatedRoom(matrixProvider, roomId);
                    return;
                  }
                  final room = await _waitForCreatedRoomByName(
                    matrixProvider,
                    groupName,
                    existingRoomIds,
                  );
                  if (!mounted) return;
                  if (room != null) {
                    matrixProvider.refreshRooms();
                    setState(() => _startingChat = false);
                    navigator.pushReplacement(
                      MaterialPageRoute(
                        builder: (_) => MatrixChatScreen(
                          room: room,
                          matrixProvider: matrixProvider,
                        ),
                      ),
                    );
                    return;
                  }
                  setState(() {
                    _startingChat = false;
                    _error = 'Failed to create group: $e';
                  });
                }
              },
              child: const Text('Create', style: TextStyle(color: kLimeGreen)),
            ),
          ],
        ),
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
          'New Chat',
          style: GoogleFonts.inter(
            color: kWhite,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      body: Column(
        children: [
          UserSearchBar(
            controller: _searchCtrl,
            onChanged: _onSearchChanged,
            onClear: () {
              _searchCtrl.clear();
              setState(() {
                _results = [];
                _publicResults = [];
                _publicRoomChannelFlags.clear();
                _error = null;
              });
            },
          ),
          if (_startingChat)
            const LoadingIndicator(message: 'Starting chat...'),
          if (_searching && !_startingChat) const LoadingIndicator(),
          if (_error != null && !_searching && !_startingChat)
            ErrorState(error: _error!),
          if (_results.isEmpty &&
              _publicResults.isEmpty &&
              !_searching &&
              !_startingChat &&
              _error == null &&
              _searchCtrl.text.isEmpty)
            Expanded(
              child: ListView(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                children: [
                  ListTile(
                    leading: const CircleAvatar(
                      backgroundColor: Color(0xFF2C2C2E),
                      child: Icon(Icons.campaign_outlined, color: kLimeGreen),
                    ),
                    title: Text(
                      'New Channel',
                      style: GoogleFonts.inter(
                          color: kWhite, fontWeight: FontWeight.w600),
                    ),
                    onTap: () {
                      _showCreateChannelDialog();
                    },
                  ),
                  ListTile(
                    leading: const CircleAvatar(
                      backgroundColor: Color(0xFF2C2C2E),
                      child: Icon(Icons.group_add_outlined, color: kLimeGreen),
                    ),
                    title: Text(
                      'New Group',
                      style: GoogleFonts.inter(
                          color: kWhite, fontWeight: FontWeight.w600),
                    ),
                    onTap: _showCreateGroupDialog,
                  ),
                ],
              ),
            ),
          if ((_results.isNotEmpty || _publicResults.isNotEmpty) &&
              !_startingChat)
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                children: [
                  if (_results.isNotEmpty) ...[
                    _buildSectionHeader('Users'),
                    ..._results.map(
                      (profile) => UserTile(
                        key: ValueKey(profile.userId),
                        profile: profile,
                        onTap: () => _startChat(profile),
                      ),
                    ),
                  ],
                  if (_publicResults.isNotEmpty) ...[
                    _buildSectionHeader('Public Rooms'),
                    ..._publicResults.map(_buildPublicRoomTile),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 14, 8, 6),
      child: Text(
        title.toUpperCase(),
        style: GoogleFonts.inter(
          color: kLightGrey,
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.1,
        ),
      ),
    );
  }

  Widget _buildPublicRoomTile(PublicRoomsChunk room) {
    final provider = context.read<MatrixProvider>();
    final joinedRoom = provider.service.getRoomById(room.roomId);
    final isJoined = joinedRoom != null;
    final isJoining = _joiningRoomIds.contains(room.roomId);
    final isChannel =
        joinedRoom?.isChannel ?? _publicRoomChannelFlags[room.roomId] ?? false;
    final name = room.name ?? room.canonicalAlias ?? room.roomId;
    final topic = room.topic ?? '';
    final roomIcon = isChannel ? Icons.campaign : Icons.group;

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      leading: StoryAvatar(
        userName: name,
        avatarUrl: room.avatarUrl?.toString(),
        size: 42,
        fallbackIcon: roomIcon,
      ),
      title: Row(
        children: [
          Flexible(
            child: Text(
              name,
              style: GoogleFonts.inter(
                color: kWhite,
                fontWeight: FontWeight.w600,
                fontSize: 14,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: kLimeGreen.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(5),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(roomIcon, color: kLimeGreen, size: 9),
                const SizedBox(width: 2),
                Text(
                  isChannel ? 'Channel' : 'Group',
                  style: GoogleFonts.inter(
                    color: kLimeGreen,
                    fontSize: 8,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      subtitle: Text(
        topic.isNotEmpty
            ? topic
            : '${room.numJoinedMembers} member${room.numJoinedMembers == 1 ? '' : 's'}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: GoogleFonts.inter(color: kLightGrey, fontSize: 12),
      ),
      trailing: isJoining
          ? const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(
                color: kLimeGreen,
                strokeWidth: 2,
              ),
            )
          : TextButton(
              onPressed: () => _openOrJoinPublicRoom(room),
              style: TextButton.styleFrom(
                backgroundColor: isJoined ? kDarkGrey : kLimeGreen,
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text(
                isJoined ? 'Open' : 'Join',
                style: GoogleFonts.inter(
                  color: isJoined ? kLimeGreen : kBlack,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
      onTap: isJoining ? null : () => _openOrJoinPublicRoom(room),
    );
  }
}
