import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:matrix/matrix.dart';
import 'package:provider/provider.dart';
import '../../theme.dart';
import '../../providers/chat_filter_provider.dart';
import '../../providers/matrix_provider.dart';
import '../../providers/story_provider.dart';

/// Category filter chips for filtering chats
class CategoryFilters extends StatelessWidget {
  const CategoryFilters({super.key});

  @override
  Widget build(BuildContext context) {
    return Selector3<ChatFilterProvider, MatrixProvider, StoryProvider, FilterData>(
      selector: (_, filterProvider, matrixProvider, storyProvider) {
        final activeRooms = matrixProvider.rooms.where((room) {
          return room.membership == Membership.join ||
              room.membership == Membership.invite;
        }).toList();
        
        // Count stories (my stories + contact stories with unviewed)
        final myUserId = matrixProvider.userId ?? '';
        final storiesCount = (storyProvider.hasMyStories ? 1 : 0) +
            storyProvider.contactStories.where((us) => !us.allViewedBy(myUserId)).length;
        
        return FilterData(
          filter: filterProvider.filter,
          allCount: activeRooms.length,
          storiesCount: storiesCount,
          groupCount: activeRooms.where((room) => room.isGroup).length,
          channelCount: activeRooms.where((room) => room.isChannel).length,
        );
      },
      builder: (context, data, _) {
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                FilterChip(
                  label: 'All',
                  badge: data.allCount.toString(),
                  isSelected: data.filter == ChatFilter.all,
                  onTap: () => context.read<ChatFilterProvider>().setFilter(ChatFilter.all),
                ),
                const SizedBox(width: 8),
                FilterChip(
                  label: 'Stories',
                  badge: data.storiesCount.toString(),
                  isSelected: data.filter == ChatFilter.stories,
                  onTap: () => context.read<ChatFilterProvider>().setFilter(ChatFilter.stories),
                ),
                const SizedBox(width: 8),
                FilterChip(
                  label: 'Groups',
                  badge: data.groupCount.toString(),
                  isSelected: data.filter == ChatFilter.groups,
                  onTap: () => context.read<ChatFilterProvider>().setFilter(ChatFilter.groups),
                ),
                const SizedBox(width: 8),
                FilterChip(
                  label: 'Channels',
                  badge: data.channelCount.toString(),
                  isSelected: data.filter == ChatFilter.channels,
                  onTap: () => context.read<ChatFilterProvider>().setFilter(ChatFilter.channels),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class FilterData {
  final ChatFilter filter;
  final int allCount;
  final int storiesCount;
  final int groupCount;
  final int channelCount;

  const FilterData({
    required this.filter,
    required this.allCount,
    required this.storiesCount,
    required this.groupCount,
    required this.channelCount,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FilterData &&
          runtimeType == other.runtimeType &&
          filter == other.filter &&
          allCount == other.allCount &&
          storiesCount == other.storiesCount &&
          groupCount == other.groupCount &&
          channelCount == other.channelCount;

  @override
  int get hashCode =>
      filter.hashCode ^
      allCount.hashCode ^
      storiesCount.hashCode ^
      groupCount.hashCode ^
      channelCount.hashCode;
}

/// Individual filter chip widget
class FilterChip extends StatelessWidget {
  final String label;
  final String badge;
  final bool isSelected;
  final VoidCallback onTap;

  const FilterChip({
    super.key,
    required this.label,
    required this.badge,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? kLimeGreen : kDarkGrey,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: GoogleFonts.inter(
                color: isSelected ? kBlack : kWhite,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 5),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                color: isSelected ? kBlack.withValues(alpha: 0.25) : kLimeGreen,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                badge,
                style: GoogleFonts.inter(
                  color: kBlack,
                  fontSize: 9,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
