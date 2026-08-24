import 'package:matrix/matrix.dart';

import '../services/matrix_service.dart';

class RoomRepository {
  const RoomRepository(this.matrixService);

  final MatrixService matrixService;

  List<Room> getRooms() => matrixService.roomRepository.getRooms();

  Future<String> createRoom({
    required String name,
    String? topic,
    bool isDirect = false,
  }) => matrixService.roomRepository.createRoom(
    name: name,
    topic: topic,
    isDirect: isDirect,
  );

  Future<String> createDirectRoom(String userId) =>
      matrixService.roomRepository.createDirectRoom(userId);

  Future<String> createChannel({
    required String name,
    String? topic,
    bool isPublic = true,
  }) => matrixService.roomRepository.createChannel(
    name: name,
    topic: topic,
    isPublic: isPublic,
  );

  Future<void> joinRoom(String roomIdOrAlias) =>
      matrixService.roomRepository.joinRoom(roomIdOrAlias);

  Future<Timeline?> getTimeline(String roomId) =>
      matrixService.roomRepository.getTimeline(roomId);
}
