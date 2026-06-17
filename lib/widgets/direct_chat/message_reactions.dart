import 'package:emoji_picker_flutter/emoji_picker_flutter.dart' as emoji_picker;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../theme.dart';

class ReactionUser {
  final String userId;
  final String displayName;
  final String? avatarUrl;

  const ReactionUser({
    required this.userId,
    required this.displayName,
    this.avatarUrl,
  });
}

class MessageReactionSummary {
  final String emoji;
  final int count;
  final bool reactedByMe;
  final List<ReactionUser> users;

  const MessageReactionSummary({
    required this.emoji,
    required this.count,
    required this.reactedByMe,
    required this.users,
  });
}

class MessageReactions extends StatelessWidget {
  final List<MessageReactionSummary> reactions;
  final ValueChanged<MessageReactionSummary> onTap;
  final bool isMyMessage;

  const MessageReactions({
    super.key,
    required this.reactions,
    required this.onTap,
    this.isMyMessage = false,
  });

  @override
  Widget build(BuildContext context) {
    if (reactions.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: EdgeInsets.only(
        top: 0,
        left: isMyMessage ? 34 : 0,
        right: isMyMessage ? 0 : 34,
      ),
      child: Transform.translate(
        offset: const Offset(0, -5),
        child: Wrap(
          alignment: isMyMessage ? WrapAlignment.end : WrapAlignment.start,
          spacing: 3,
          runSpacing: 3,
          children: reactions.map((reaction) {
            final showsCount = reaction.count > 1;
            return InkWell(
              onTap: () => onTap(reaction),
              customBorder: const StadiumBorder(),
              child: Container(
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                padding: EdgeInsets.symmetric(
                  horizontal: showsCount ? 6 : 0,
                  vertical: 0,
                ),
                decoration: BoxDecoration(
                  color: reaction.reactedByMe
                      ? const Color(0xFF242426)
                      : kDarkerGrey,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: Colors.black, width: 0.7),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      reaction.emoji,
                      style: const TextStyle(fontSize: 16, height: 1),
                    ),
                    if (showsCount) ...[
                      const SizedBox(width: 3),
                      Text(
                        '${reaction.count}',
                        style: GoogleFonts.inter(
                          color: reaction.reactedByMe ? kLimeGreen : kWhite,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            );
          }).toList(growable: false),
        ),
      ),
    );
  }
}

class _ReactionCategory {
  final String label;
  final IconData icon;
  final List<String> emojis;

  const _ReactionCategory({
    required this.label,
    required this.icon,
    required this.emojis,
  });
}

class ReactionPicker extends StatefulWidget {
  final String? selectedEmoji;
  final ValueChanged<String> onReactionSelected;
  final bool closeOnSelection;
  final Widget? composer;

  const ReactionPicker({
    super.key,
    this.selectedEmoji,
    required this.onReactionSelected,
    this.closeOnSelection = true,
    this.composer,
  });

  static final List<_ReactionCategory> _categories = _buildCategories();

  static List<_ReactionCategory> _buildCategories() {
    return List.unmodifiable([
      _ReactionCategory(
        label: 'Smileys and people',
        icon: Icons.sentiment_satisfied_alt_rounded,
        emojis: _baseEmojis(
          _packageEntries(emoji_picker.Category.SMILEYS),
        ),
      ),
      _packageCategory(
        label: 'Animals and nature',
        icon: Icons.pets_rounded,
        category: emoji_picker.Category.ANIMALS,
      ),
      _packageCategory(
        label: 'Food and drinks',
        icon: Icons.restaurant_rounded,
        category: emoji_picker.Category.FOODS,
      ),
      _packageCategory(
        label: 'Activity',
        icon: Icons.sports_soccer_rounded,
        category: emoji_picker.Category.ACTIVITIES,
      ),
      _packageCategory(
        label: 'Travel and places',
        icon: Icons.directions_car_filled_rounded,
        category: emoji_picker.Category.TRAVEL,
      ),
      _packageCategory(
        label: 'Objects',
        icon: Icons.lightbulb_rounded,
        category: emoji_picker.Category.OBJECTS,
      ),
      _packageCategory(
        label: 'Symbols',
        icon: Icons.category_rounded,
        category: emoji_picker.Category.SYMBOLS,
      ),
      _packageCategory(
        label: 'Flags',
        icon: Icons.flag_rounded,
        category: emoji_picker.Category.FLAGS,
      ),
    ]);
  }

  static _ReactionCategory _packageCategory({
    required String label,
    required IconData icon,
    required emoji_picker.Category category,
  }) {
    return _ReactionCategory(
      label: label,
      icon: icon,
      emojis: _baseEmojis(_packageEntries(category)),
    );
  }

  static List<emoji_picker.Emoji> _packageEntries(
    emoji_picker.Category category,
  ) {
    return emoji_picker.defaultEmojiSet
        .firstWhere((entry) => entry.category == category)
        .emoji;
  }

  static List<String> _baseEmojis(Iterable<emoji_picker.Emoji> entries) {
    return List.unmodifiable(
      entries
          .map((entry) => entry.emoji)
          .where((emoji) => !_containsSkinToneModifier(emoji))
          .toSet(),
    );
  }

  static bool _containsSkinToneModifier(String emoji) {
    return emoji.runes.any(
      (rune) => rune >= 0x1F3FB && rune <= 0x1F3FF,
    );
  }

  static final List<String> quickReactions = List.unmodifiable(
    _categories.expand((category) => category.emojis).toSet(),
  );

  @override
  State<ReactionPicker> createState() => _ReactionPickerState();

  static void show(
    BuildContext context,
    ValueChanged<String> onReactionSelected, {
    String? selectedEmoji,
    bool closeOnSelection = true,
    Widget? composer,
  }) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => ReactionPicker(
        selectedEmoji: selectedEmoji,
        onReactionSelected: onReactionSelected,
        closeOnSelection: closeOnSelection,
        composer: composer,
      ),
    );
  }
}

class _ReactionPickerState extends State<ReactionPicker>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    var initialIndex = 0;
    if (widget.selectedEmoji != null) {
      final selectedIndex = ReactionPicker._categories.indexWhere(
        (category) => category.emojis.contains(widget.selectedEmoji),
      );
      if (selectedIndex >= 0) initialIndex = selectedIndex;
    }
    _tabController = TabController(
      length: ReactionPicker._categories.length,
      initialIndex: initialIndex,
      vsync: this,
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final maxHeight = MediaQuery.sizeOf(context).height * 0.58;
    final hasComposer = widget.composer != null;

    return SafeArea(
      child: SizedBox(
        height: maxHeight,
        child: Column(
          children: [
            if (hasComposer) ...[
              widget.composer!,
              const Divider(
                height: 1,
                thickness: 1,
                color: Color(0xFF2C2C2E),
              ),
            ],
            Expanded(
              child: Container(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                decoration: BoxDecoration(
                  color: const Color(0xFF151515),
                  borderRadius: hasComposer
                      ? BorderRadius.zero
                      : const BorderRadius.vertical(top: Radius.circular(22)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (!hasComposer) ...[
                      Center(
                        child: Container(
                          width: 38,
                          height: 4,
                          decoration: BoxDecoration(
                            color: kMediumGrey,
                            borderRadius: BorderRadius.circular(99),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                    ],
                    Expanded(
                      child: TabBarView(
                        controller: _tabController,
                        children: ReactionPicker._categories
                            .map(
                              (category) => _buildEmojiGrid(category.emojis),
                            )
                            .toList(growable: false),
                      ),
                    ),
                    const SizedBox(height: 4),
                    TabBar(
                      controller: _tabController,
                      isScrollable: true,
                      tabAlignment: TabAlignment.start,
                      padding: EdgeInsets.zero,
                      labelPadding: const EdgeInsets.symmetric(horizontal: 12),
                      dividerColor: Colors.transparent,
                      indicatorColor: kWhite,
                      indicatorSize: TabBarIndicatorSize.label,
                      labelColor: kWhite,
                      unselectedLabelColor: const Color(0xFF8E8E93),
                      tabs: ReactionPicker._categories
                          .map(
                            (category) => Tooltip(
                              message: category.label,
                              child: Tab(
                                height: 42,
                                icon: Icon(category.icon, size: 23),
                              ),
                            ),
                          )
                          .toList(growable: false),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmojiGrid(List<String> emojis) {
    return GridView.builder(
      padding: const EdgeInsets.only(bottom: 8),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 9,
        mainAxisSpacing: 0,
        crossAxisSpacing: 0,
      ),
      itemCount: emojis.length,
      itemBuilder: (context, index) {
        final emoji = emojis[index];
        final selected = emoji == widget.selectedEmoji;
        return InkWell(
          onTap: () {
            if (widget.closeOnSelection) {
              Navigator.pop(context);
            }
            widget.onReactionSelected(emoji);
          },
          borderRadius: BorderRadius.circular(14),
          child: Container(
            decoration: BoxDecoration(
              color: selected ? const Color(0xFF3A3A3C) : Colors.transparent,
              borderRadius: BorderRadius.circular(14),
            ),
            alignment: Alignment.center,
            child: Text(
              emoji,
              style: const TextStyle(fontSize: 24),
            ),
          ),
        );
      },
    );
  }
}
