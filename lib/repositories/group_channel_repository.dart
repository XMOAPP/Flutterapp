import '../models/invite_link_models.dart';
import '../services/matrix_service.dart';

class GroupChannelRepository {
  const GroupChannelRepository(this.matrixService);

  final MatrixService matrixService;

  Future<XmoInviteLink> generateTrackedInviteLink(String roomId) =>
      matrixService.communityRepository.generateTrackedInviteLink(roomId);

  Future<List<XmoInviteLink>> getInviteLinks(String roomId) =>
      matrixService.communityRepository.getInviteLinks(roomId);

  Future<void> revokeInviteLink(String roomId, String linkId) =>
      matrixService.communityRepository.revokeInviteLink(roomId, linkId);

  Future<void> markRoomAsDirect(String roomId, String otherUserId) =>
      matrixService.communityRepository.markRoomAsDirect(roomId, otherUserId);

  Future<void> repairDirectChatMappings() =>
      matrixService.communityRepository.repairDirectChatMappings();
}
