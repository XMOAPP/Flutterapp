import 'package:matrix/matrix.dart';

class MessageReplyReference {
  final String roomId;
  final String eventId;

  const MessageReplyReference({
    required this.roomId,
    required this.eventId,
  });

  factory MessageReplyReference.fromEvent(Event event) {
    return MessageReplyReference(
      roomId: event.room.id,
      eventId: event.eventId,
    );
  }

  Map<String, dynamic> toJson() => {
        'roomId': roomId,
        'eventId': eventId,
      };

  factory MessageReplyReference.fromJson(Map<dynamic, dynamic> json) {
    return MessageReplyReference(
      roomId: json['roomId'] as String? ?? '',
      eventId: json['eventId'] as String? ?? '',
    );
  }
}
