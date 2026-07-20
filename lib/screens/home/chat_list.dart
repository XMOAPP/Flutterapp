import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart';
import 'package:provider/provider.dart';
import '../../providers/chat_filter_provider.dart';
import '../../providers/matrix_provider.dart';
import '../../services/chat_archive_service.dart';
import 'calls_view.dart';
import 'matrix_room_tile.dart';
import 'stories_view.dart';

/// Main chat list body with filtering and search - Matrix only
class ChatList extends StatelessWidget {
  const ChatList({super.key});

  @override
  Widget build(BuildContext context) {
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
            final archiveCode = ChatArchiveService.isArchived(room) ? 'a' : '-';
            return '${room.id}:${room.membership.name}:$typeCode:$archiveCode';
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
              lastEvent?.messageType,
              lastEvent?.body,
              lastEvent?.content['filename'],
              lastEvent?.content['msgtype'],
              lastEvent?.redacted,
              lastEvent?.originServerTs.millisecondsSinceEpoch,
            ].join(':');
          }).join('|'),
        );
      },
      shouldRebuild: (prev, next) => prev != next,
      builder: (context, data, _) {
        if (data.filter == ChatFilter.stories) {
          return const StoriesView();
        }
        if (data.filter == ChatFilter.calls) {
          return const CallsView();
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
          final isActive = room.membership == Membership.join ||
              room.membership == Membership.invite;
          return isActive && !ChatArchiveService.isArchived(room);
        }).toList();

        // Filter by type based on selected filter
        final filteredRooms = activeRooms.where((room) {
          if (matrixService.isSavedMessagesRoom(room)) return false;
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
