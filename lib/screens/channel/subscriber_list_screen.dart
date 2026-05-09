import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:matrix/matrix.dart';
import 'package:provider/provider.dart';
import '../../theme.dart';
import '../../providers/matrix_provider.dart';
import '../../services/channel_service.dart';
import '../../models/channel_models.dart';

/// Subscriber List Screen - View and manage channel subscribers
class SubscriberListScreen extends StatefulWidget {
  final Room room;
  final List<ChannelSubscriber> subscribers;

  const SubscriberListScreen({
    super.key,
    required this.room,
    required this.subscribers,
  });

  @override
  State<SubscriberListScreen> createState() => _SubscriberListScreenState();
}

class _SubscriberListScreenState extends State<SubscriberListScreen> {
  late ChannelService _channelService;
  final _searchCtrl = TextEditingController();
  List<ChannelSubscriber> _filteredSubscribers = [];
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    final matrixProvider = context.read<MatrixProvider>();
    _channelService = ChannelService(matrixProvider.service);
    _filteredSubscribers = widget.subscribers;
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _filterSubscribers(String query) {
    setState(() {
      if (query.isEmpty) {
        _filteredSubscribers = widget.subscribers;
      } else {
        _filteredSubscribers = widget.subscribers
            .where((sub) =>
                sub.displayName.toLowerCase().contains(query.toLowerCase()) ||
                sub.userId.toLowerCase().contains(query.toLowerCase()))
            .toList();
      }
    });
  }

  bool get _isAdmin => widget.room.ownPowerLevel >= 50;

  Future<void> _banSubscriber(ChannelSubscriber subscriber) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: kDarkerGrey,
        title: Text('Ban Subscriber?', style: GoogleFonts.inter(color: kWhite)),
        content: Text(
          'Ban ${subscriber.displayName} from this channel?',
          style: GoogleFonts.inter(color: kLightGrey),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel', style: GoogleFonts.inter(color: kLightGrey)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Ban', style: GoogleFonts.inter(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _loading = true);
    try {
      await _channelService.banSubscriber(widget.room.id, subscriber.userId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${subscriber.displayName} has been banned'),
            backgroundColor: kLimeGreen,
          ),
        );
        Navigator.pop(context, true); // Return true to reload data
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to ban: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
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
          icon: const Icon(Icons.arrow_back, color: kWhite),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Subscribers (${widget.subscribers.length})',
          style: GoogleFonts.inter(
            color: kWhite,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      body: Column(
        children: [
          // Search Bar
          Container(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _searchCtrl,
              style: GoogleFonts.inter(color: kWhite),
              onChanged: _filterSubscribers,
              decoration: InputDecoration(
                hintText: 'Search subscribers...',
                hintStyle: GoogleFonts.inter(color: kLightGrey),
                prefixIcon: const Icon(Icons.search, color: kLightGrey),
                filled: true,
                fillColor: kDarkerGrey,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              ),
            ),
          ),

          // Subscriber List
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(color: kLimeGreen))
                : _filteredSubscribers.isEmpty
                    ? Center(
                        child: Text(
                          'No subscribers found',
                          style: GoogleFonts.inter(color: kLightGrey),
                        ),
                      )
                    : ListView.builder(
                        itemCount: _filteredSubscribers.length,
                        itemBuilder: (context, index) {
                          final subscriber = _filteredSubscribers[index];
                          return _buildSubscriberTile(subscriber);
                        },
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildSubscriberTile(ChannelSubscriber subscriber) {
    final myUserId = context.read<MatrixProvider>().userId ?? '';
    final isMe = subscriber.userId == myUserId;

    return ListTile(
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: CircleAvatar(
        radius: 16,
        backgroundColor: kDarkGrey,
        child: Text(
          subscriber.displayName.isNotEmpty
              ? subscriber.displayName[0].toUpperCase()
              : '?',
          style: GoogleFonts.inter(
            color: kLimeGreen,
            fontWeight: FontWeight.bold,
            fontSize: 12,
          ),
        ),
      ),
      title: Row(
        children: [
          Expanded(
            child: Text(
              subscriber.displayName + (isMe ? ' (You)' : ''),
              style: GoogleFonts.inter(color: kWhite, fontSize: 13),
            ),
          ),
          if (subscriber.isAdmin)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: kLimeGreen.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: kLimeGreen, width: 1),
              ),
              child: Text(
                'Admin',
                style: GoogleFonts.inter(
                  color: kLimeGreen,
                  fontSize: 9,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
        ],
      ),
      subtitle: Text(
        subscriber.userId,
        style: GoogleFonts.inter(color: kLightGrey, fontSize: 11),
      ),
      trailing: _isAdmin && !isMe && !subscriber.isAdmin
          ? IconButton(
              icon: const Icon(Icons.block, color: Colors.red, size: 18),
              onPressed: () => _banSubscriber(subscriber),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            )
          : null,
    );
  }
}
