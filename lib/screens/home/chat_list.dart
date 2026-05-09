import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart';
import 'package:provider/provider.dart';
import '../../providers/chat_filter_provider.dart';
import '../../providers/matrix_provider.dart';
import '../../services/app_settings_service.dart';
import 'matrix_room_tile.dart';

/// Main chat list body with filtering and search - Matrix only
class ChatList extends StatelessWidget {
  const ChatList({super.key});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<AppSettings>(
      future: AppSettingsService().load(),
      builder: (context, settingsSnapshot) {
        final showUnreadBadge =
            settingsSnapshot.data?.notificationsEnabled ?? true;

        return Selector2<ChatFilterProvider, MatrixProvider, ChatListData>(
      selector: (_, filterProvider, matrixProvider) {
        final matrixService = matrixProvider.service;
        return ChatListData(
          filter: filterProvider.filter,
          searchQuery: filterProvider.searchQuery,
          isLoggedIn: matrixProvider.isLoggedIn,
          rooms: matrixProvider.rooms,
          roomTypeSignature: matrixProvider.rooms.map((room) {
            final typeCode = room.isChannel
                ? 'c'
                : room.isGroup
                    ? 'g'
                    : matrixService.isDirectRoom(room)
                        ? 'd'
                        : 'u';
            return '${room.id}:${room.membership.name}:$typeCode';
          }).join('|'),
          roomPreviewSignature: matrixProvider.rooms.map((room) {
            final lastEvent = room.lastEvent;
            return [
              room.id,
              room.name,
              room.topic,
              room.avatar,
              room.notificationCount,
              room.highlightCount,
              lastEvent?.eventId,
              lastEvent?.type,
              lastEvent?.body,
            ].join(':');
          }).join('|'),
        );
      },
      shouldRebuild: (prev, next) => prev != next,
      builder: (context, data, _) {
        // Stories feature removed - was demo only
        if (data.filter == ChatFilter.stories) {
          return const Center(
            child: Text(
              'Stories feature coming soon',
              style: TextStyle(color: Colors.white54),
            ),
          );
        }

        if (!data.isLoggedIn) {
          return const Center(
            child: Text(
              'Please log in to view chats',
              style: TextStyle(color: Colors.white54),
            ),
          );
        }

        final searchLower = data.searchQuery.toLowerCase();
        final matrixService = context.read<MatrixProvider>().service;
        final matrixRooms = searchLower.isEmpty
            ? data.rooms
            : data.rooms.where((r) {
                return matrixService
                    .getResolvedDisplayName(r)
                    .toLowerCase()
                    .contains(searchLower);
              }).toList();

        // Filter out rooms where user has left or been kicked
        final activeRooms = matrixRooms.where((room) {
          return room.membership == Membership.join ||
              room.membership == Membership.invite;
        }).toList();

        // Filter by type based on selected filter
        final filteredRooms = activeRooms.where((room) {
          if (data.filter == ChatFilter.groups) {
            return room.isGroup;
          } else if (data.filter == ChatFilter.channels) {
            return room.isChannel;
          }
          return true; // ChatFilter.all
        }).toList();

        if (filteredRooms.isEmpty) {
          if (data.filter == ChatFilter.channels) {
            return const Center(
              child: Text(
                "Use the search bar to discover channels",
                style: TextStyle(color: Colors.white38, fontSize: 13),
              ),
            );
          }
          return const Center(
            child:
                Text('No chats found', style: TextStyle(color: Colors.white54)),
          );
        }

        return ListView.builder(
          padding: EdgeInsets.zero,
          itemCount: filteredRooms.length,
          itemBuilder: (context, index) {
            final room = filteredRooms[index];
            return MatrixRoomTile(
              key: ValueKey(room.id),
              room: room,
              showUnreadBadge: showUnreadBadge,
            );
          },
        );
      },
    );
      },
    );
  }
}

/// Data class for Selector optimization
class ChatListData {
  final ChatFilter filter;
  final String searchQuery;
  final bool isLoggedIn;
  final List<Room> rooms;
  final String roomTypeSignature;
  final String roomPreviewSignature;

  const ChatListData({
    required this.filter,
    required this.searchQuery,
    required this.isLoggedIn,
    required this.rooms,
    required this.roomTypeSignature,
    required this.roomPreviewSignature,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ChatListData &&
          runtimeType == other.runtimeType &&
          filter == other.filter &&
          searchQuery == other.searchQuery &&
          isLoggedIn == other.isLoggedIn &&
          rooms.length == other.rooms.length &&
          roomTypeSignature == other.roomTypeSignature &&
          roomPreviewSignature == other.roomPreviewSignature;

  @override
  int get hashCode =>
      filter.hashCode ^
      searchQuery.hashCode ^
      isLoggedIn.hashCode ^
      rooms.length.hashCode ^
      roomTypeSignature.hashCode ^
      roomPreviewSignature.hashCode;
}
