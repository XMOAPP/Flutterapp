import 'package:flutter_test/flutter_test.dart';
import 'package:xmo/utils/message_presentation.dart';

Map<String, dynamic> _replyContent(String body) => {
      'body': body,
      'm.relates_to': {
        'm.in_reply_to': {'event_id': r'$original'},
      },
    };

void main() {
  group('Matrix reply presentation', () {
    test('removes the plain-text fallback from a real reply', () {
      final content = _replyContent(
        '> <@six:example.org> Original message\n> second line\n\nVisible reply',
      );

      expect(matrixVisibleBodyFromContent(content), 'Visible reply');
    });

    test('supports CRLF reply fallbacks', () {
      final content = _replyContent(
        '> <@six:example.org> Original\r\n\r\nVisible reply',
      );

      expect(matrixVisibleBodyFromContent(content), 'Visible reply');
    });

    test('preserves quoted text without a reply relation', () {
      const body = '> this is intentionally quoted\n\nMy note';

      expect(
        matrixVisibleBodyFromContent({'body': body}),
        body,
      );
    });

    test('preserves malformed reply fallbacks without a separator', () {
      final content = _replyContent(
        '> <@six:example.org> Original\nVisible reply',
      );

      expect(
        matrixVisibleBodyFromContent(content),
        '> <@six:example.org> Original\nVisible reply',
      );
    });

    test('removes formatted fallback only from a real reply', () {
      const html =
          '<mx-reply><blockquote>Original</blockquote></mx-reply><b>Reply</b>';

      expect(
        stripMatrixFormattedReplyFallback(html, isReply: true),
        '<b>Reply</b>',
      );
      expect(
        stripMatrixFormattedReplyFallback(html, isReply: false),
        html,
      );
    });

    test('uses edited reply content instead of the replacement fallback', () {
      final content = {
        'msgtype': 'm.text',
        'body': '* > <@varunn:example.org> Original message\n\nOld reply',
        'm.relates_to': {
          'rel_type': 'm.replace',
          'event_id': r'$reply',
        },
        'm.new_content': {
          'msgtype': 'm.text',
          'body': '> <@varunn:example.org> Original message\n\nEdited reply',
          'm.relates_to': {
            'm.in_reply_to': {'event_id': r'$original'},
          },
        },
      };

      expect(matrixVisibleBodyFromContent(content), 'Edited reply');
      expect(matrixReplyEventIdFromContent(content), r'$original');
    });

    test('ignores unvalidated new content on a normal message', () {
      final content = {
        'body': 'Visible message',
        'm.new_content': {'body': 'Unexpected replacement'},
      };

      expect(matrixVisibleBodyFromContent(content), 'Visible message');
    });
  });

  group('Matrix attachment names', () {
    test('prefers the protocol filename over body and reply fallback', () {
      final content = _replyContent(
        '> <@six:example.org> Original\n\nCaption',
      )..['filename'] = 'report.pdf';

      expect(
        matrixAttachmentFileNameFromContent(content),
        'report.pdf',
      );
    });

    test('uses the visible reply body when filename is absent', () {
      final content = _replyContent(
        '> <@six:example.org> Original\n\nreport.pdf',
      );

      expect(
        matrixAttachmentFileNameFromContent(content),
        'report.pdf',
      );
    });

    test('sanitizes paths and unsafe filename characters', () {
      expect(
        sanitizeAttachmentFileName(r'C:\temp\bad:name?.pdf'),
        'bad_name_.pdf',
      );
    });
  });
}
