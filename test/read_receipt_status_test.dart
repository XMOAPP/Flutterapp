import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';
import 'package:xmo/widgets/direct_chat/read_receipt.dart';

void main() {
  group('resolveReadReceiptStatus', () {
    test('maps the complete outgoing event lifecycle', () {
      expect(
        resolveReadReceiptStatus(EventStatus.error),
        ReadReceiptStatus.failed,
      );
      expect(
        resolveReadReceiptStatus(EventStatus.sending),
        ReadReceiptStatus.sending,
      );
      expect(
        resolveReadReceiptStatus(EventStatus.sent),
        ReadReceiptStatus.sent,
      );
      expect(
        resolveReadReceiptStatus(EventStatus.synced),
        ReadReceiptStatus.delivered,
      );
      expect(
        resolveReadReceiptStatus(EventStatus.synced, isRead: true),
        ReadReceiptStatus.read,
      );
    });

    test('does not report an unsynced event as read', () {
      expect(
        resolveReadReceiptStatus(EventStatus.sent, isRead: true),
        ReadReceiptStatus.sent,
      );
    });
  });
}
