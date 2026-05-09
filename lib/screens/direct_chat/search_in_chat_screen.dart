import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:matrix/matrix.dart';
import 'package:provider/provider.dart';
import '../../theme.dart';
import '../../providers/matrix_provider.dart';
import '../../services/direct_chat_service.dart';
import '../../services/matrix_service.dart';

/// Search in Chat Screen - Search messages in direct chat
class SearchInChatScreen extends StatefulWidget {
  final Room room;

  const SearchInChatScreen({
    super.key,
    required this.room,
  });

  @override
  State<SearchInChatScreen> createState() => _SearchInChatScreenState();
}

class _SearchInChatScreenState extends State<SearchInChatScreen> {
  final _searchController = TextEditingController();
  late DirectChatService _directChatService;
  
  List<Event> _results = [];
  bool _searching = false;
  bool _hasSearched = false;

  @override
  void initState() {
    super.initState();
    final matrixProvider = context.read<MatrixProvider>();
    _directChatService = DirectChatService(matrixProvider.service);
  }

  Future<void> _search(String query) async {
    if (query.trim().isEmpty) {
      setState(() {
        _results = [];
        _hasSearched = false;
      });
      return;
    }

    setState(() => _searching = true);
    
    try {
      final results = await _directChatService.searchMessages(
        widget.room.id,
        query,
      );
      
      if (mounted) {
        setState(() {
          _results = results;
          _searching = false;
          _hasSearched = true;
        });
      }
    } catch (e) {
      debugPrint('[SearchInChat] Error searching: $e');
      if (mounted) {
        setState(() {
          _searching = false;
          _hasSearched = true;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Search failed: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
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
        title: TextField(
          controller: _searchController,
          autofocus: true,
          style: GoogleFonts.inter(color: kWhite, fontSize: 16),
          decoration: InputDecoration(
            hintText: 'Search messages...',
            hintStyle: GoogleFonts.inter(color: kLightGrey),
            border: InputBorder.none,
            suffixIcon: _searchController.text.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.clear, color: kLightGrey),
                    onPressed: () {
                      _searchController.clear();
                      _search('');
                    },
                  )
                : null,
          ),
          onChanged: (value) {
            setState(() {}); // Update UI for clear button
          },
          onSubmitted: _search,
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.search, color: kLimeGreen),
            onPressed: () => _search(_searchController.text),
          ),
        ],
      ),
      body: _searching
          ? const Center(child: CircularProgressIndicator(color: kLimeGreen))
          : !_hasSearched
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.search,
                        color: kMediumGrey,
                        size: 64,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Search for messages',
                        style: GoogleFonts.inter(
                          color: kLightGrey,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Enter a search term above',
                        style: GoogleFonts.inter(
                          color: kLightGrey,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                )
              : _results.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.search_off,
                            color: kMediumGrey,
                            size: 64,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'No results found',
                            style: GoogleFonts.inter(
                              color: kLightGrey,
                              fontSize: 16,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Try a different search term',
                            style: GoogleFonts.inter(
                              color: kLightGrey,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: _results.length,
                      itemBuilder: (_, i) => _buildResultTile(_results[i]),
                    ),
    );
  }

  Widget _buildResultTile(Event event) {
    final senderName = MatrixService.cleanName(event.senderId);
    final time = _formatTime(event.originServerTs);
    final query = _searchController.text.toLowerCase();
    
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: kDarkerGrey,
        borderRadius: BorderRadius.circular(12),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.all(16),
        title: Row(
          children: [
            Text(
              senderName,
              style: GoogleFonts.inter(
                color: kLimeGreen,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              time,
              style: GoogleFonts.inter(
                color: kLightGrey,
                fontSize: 11,
              ),
            ),
          ],
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 8),
          child: _buildHighlightedText(event.body, query),
        ),
        onTap: () => _navigateToMessage(event),
      ),
    );
  }

  Widget _buildHighlightedText(String text, String query) {
    if (query.isEmpty) {
      return Text(
        text,
        style: GoogleFonts.inter(color: kWhite, fontSize: 14),
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
      );
    }

    final lowerText = text.toLowerCase();
    final lowerQuery = query.toLowerCase();
    final spans = <TextSpan>[];
    
    int start = 0;
    int index = lowerText.indexOf(lowerQuery);
    
    while (index != -1) {
      // Add text before match
      if (index > start) {
        spans.add(TextSpan(
          text: text.substring(start, index),
          style: GoogleFonts.inter(color: kWhite),
        ));
      }
      
      // Add highlighted match
      spans.add(TextSpan(
        text: text.substring(index, index + query.length),
        style: GoogleFonts.inter(
          color: kBlack,
          backgroundColor: kLimeGreen,
          fontWeight: FontWeight.bold,
        ),
      ));
      
      start = index + query.length;
      index = lowerText.indexOf(lowerQuery, start);
    }
    
    // Add remaining text
    if (start < text.length) {
      spans.add(TextSpan(
        text: text.substring(start),
        style: GoogleFonts.inter(color: kWhite),
      ));
    }

    return RichText(
      text: TextSpan(children: spans),
      maxLines: 3,
      overflow: TextOverflow.ellipsis,
    );
  }

  String _formatTime(DateTime dt) {
    final now = DateTime.now();
    final difference = now.difference(dt);

    if (difference.inDays == 0) {
      // Today - show time
      final hour = dt.hour;
      final minute = dt.minute.toString().padLeft(2, '0');
      if (hour == 0) {
        return '12:$minute AM';
      } else if (hour < 12) {
        return '$hour:$minute AM';
      } else if (hour == 12) {
        return '12:$minute PM';
      } else {
        return '${hour - 12}:$minute PM';
      }
    } else if (difference.inDays == 1) {
      return 'Yesterday';
    } else if (difference.inDays < 7) {
      return '${difference.inDays} days ago';
    } else {
      return '${dt.day}/${dt.month}/${dt.year}';
    }
  }

  void _navigateToMessage(Event event) {
    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Navigate to message: ${event.body.substring(0, 30)}...'),
        backgroundColor: kDarkerGrey,
        duration: const Duration(seconds: 2),
      ),
    );
    // TODO: Implement scroll to message in chat screen
  }
}
