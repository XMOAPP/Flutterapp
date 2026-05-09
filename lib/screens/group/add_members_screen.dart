import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:matrix/matrix.dart';
import 'package:provider/provider.dart';
import '../../theme.dart';
import '../../providers/matrix_provider.dart';
import '../../services/group_service.dart';

/// Add Members Screen - Search and invite users to the group
class AddMembersScreen extends StatefulWidget {
  final Room room;

  const AddMembersScreen({super.key, required this.room});

  @override
  State<AddMembersScreen> createState() => _AddMembersScreenState();
}

class _AddMembersScreenState extends State<AddMembersScreen> {
  final _searchCtrl = TextEditingController();
  late GroupService _groupService;
  List<Profile> _results = [];
  final Set<String> _selectedUsers = {};
  bool _searching = false;
  bool _adding = false;
  String? _error;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    final matrixProvider = context.read<MatrixProvider>();
    _groupService = GroupService(matrixProvider.service);
  }

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
    final results = await provider.searchUsers(query);
    
    // Filter out users already in the group
    final currentMembers = widget.room.getParticipants().map((u) => u.id).toSet();
    final filtered = results.where((p) => !currentMembers.contains(p.userId)).toList();

    if (filtered.isNotEmpty) {
      if (mounted) {
        setState(() {
          _results = filtered;
          _searching = false;
        });
      }
      return;
    }

    // Try direct Matrix ID lookup
    String matrixId = query.trim();
    if (!matrixId.startsWith('@')) {
      matrixId = '@$matrixId';
    }
    if (!matrixId.contains(':')) {
      matrixId = '$matrixId:localhost';
    }

    try {
      final profile = await provider.service.client.getProfileFromUserId(matrixId);
      if (mounted && !currentMembers.contains(profile.userId)) {
        setState(() {
          _results = [profile];
          _searching = false;
        });
        return;
      }
    } catch (e) {
      debugPrint('Direct Matrix ID lookup failed: $e');
    }

    if (mounted) {
      setState(() {
        _results = [];
        _searching = false;
        _error = 'No users found for "$query"';
      });
    }
  }

  void _toggleUser(String userId) {
    setState(() {
      if (_selectedUsers.contains(userId)) {
        _selectedUsers.remove(userId);
      } else {
        _selectedUsers.add(userId);
      }
    });
  }

  Future<void> _addSelectedMembers() async {
    if (_selectedUsers.isEmpty) return;

    setState(() => _adding = true);
    
    int successCount = 0;
    int failCount = 0;

    for (final userId in _selectedUsers) {
      try {
        await _groupService.addMember(widget.room.id, userId);
        successCount++;
      } catch (e) {
        debugPrint('[AddMembers] Failed to add $userId: $e');
        failCount++;
      }
    }

    if (mounted) {
      setState(() => _adding = false);
      
      if (successCount > 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Added $successCount member${successCount > 1 ? 's' : ''}'),
            backgroundColor: kLimeGreen,
          ),
        );
        Navigator.pop(context, true); // Return true to indicate members were added
      }
      
      if (failCount > 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to add $failCount member${failCount > 1 ? 's' : ''}'),
            backgroundColor: Colors.red,
          ),
        );
      }
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
          icon: const Icon(Icons.close, color: kWhite),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Add Members',
          style: GoogleFonts.inter(
            color: kWhite,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
        actions: [
          if (_selectedUsers.isNotEmpty)
            TextButton(
              onPressed: _adding ? null : _addSelectedMembers,
              child: _adding
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        color: kLimeGreen,
                        strokeWidth: 2,
                      ),
                    )
                  : Text(
                      'Add (${_selectedUsers.length})',
                      style: GoogleFonts.inter(
                        color: kLimeGreen,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
            ),
        ],
      ),
      body: Column(
        children: [
          // Search Bar
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _searchCtrl,
              style: const TextStyle(color: kWhite),
              decoration: InputDecoration(
                hintText: 'Search by username...',
                hintStyle: const TextStyle(color: Colors.white54),
                prefixIcon: const Icon(Icons.search, color: kLightGrey),
                suffixIcon: _searchCtrl.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, color: kLightGrey),
                        onPressed: () {
                          _searchCtrl.clear();
                          setState(() {
                            _results = [];
                            _error = null;
                          });
                        },
                      )
                    : null,
                filled: true,
                fillColor: kDarkerGrey,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              ),
              onChanged: _onSearchChanged,
              autofocus: true,
            ),
          ),
          
          // Results
          Expanded(
            child: _searching
                ? const Center(child: CircularProgressIndicator(color: kLimeGreen))
                : _error != null
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(
                            _error!,
                            style: GoogleFonts.inter(
                              color: kLightGrey,
                              fontSize: 14,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      )
                    : _results.isEmpty && _searchCtrl.text.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.person_search,
                                  color: kMediumGrey,
                                  size: 64,
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  'Search for users to add',
                                  style: GoogleFonts.inter(
                                    color: kLightGrey,
                                    fontSize: 14,
                                  ),
                                ),
                              ],
                            ),
                          )
                        : ListView.builder(
                            itemCount: _results.length,
                            itemBuilder: (_, i) => _buildUserTile(_results[i]),
                          ),
          ),
        ],
      ),
    );
  }

  Widget _buildUserTile(Profile profile) {
    final isSelected = _selectedUsers.contains(profile.userId);
    final displayName = profile.displayName ?? profile.userId.split(':').first.replaceFirst('@', '');
    
    return ListTile(
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: CircleAvatar(
        radius: 16,
        backgroundColor: kDarkGrey,
        child: Text(
          displayName.isNotEmpty ? displayName[0].toUpperCase() : '?',
          style: GoogleFonts.inter(
            color: kLimeGreen,
            fontWeight: FontWeight.bold,
            fontSize: 12,
          ),
        ),
      ),
      title: Text(
        displayName,
        style: GoogleFonts.inter(color: kWhite, fontSize: 13),
      ),
      subtitle: Text(
        profile.userId,
        style: GoogleFonts.inter(color: kLightGrey, fontSize: 11),
      ),
      trailing: Checkbox(
        value: isSelected,
        onChanged: (_) => _toggleUser(profile.userId),
        activeColor: kLimeGreen,
        checkColor: kBlack,
      ),
      onTap: () => _toggleUser(profile.userId),
    );
  }
}
