import 'package:matrix/matrix.dart';

String? matrixReplyEventId(Event event) =>
    matrixReplyEventIdFromContent(event.content);

String? matrixReplyEventIdFromContent(Map<dynamic, dynamic> content) {
  final effectiveContent = matrixEffectiveMessageContent(content);
  final relatesTo = effectiveContent['m.relates_to'];
  if (relatesTo is! Map) return null;
  final inReplyTo = relatesTo['m.in_reply_to'];
  if (inReplyTo is! Map) return null;
  final eventId = inReplyTo['event_id'];
  return eventId is String && eventId.isNotEmpty ? eventId : null;
}

bool hasMatrixReply(Event event) => matrixReplyEventId(event) != null;

bool hasMatrixReplyContent(Map<dynamic, dynamic> content) =>
    matrixReplyEventIdFromContent(content) != null;

String matrixVisibleBody(Event event, {String fallback = ''}) =>
    matrixVisibleBodyFromContent(event.content, fallback: fallback);

String matrixVisibleBodyFromContent(
  Map<dynamic, dynamic> content, {
  String fallback = '',
}) {
  final effectiveContent = matrixEffectiveMessageContent(content);
  final rawBody = effectiveContent['body'];
  if (rawBody is! String || rawBody.trim().isEmpty) return fallback;
  final visible = stripMatrixReplyFallback(
    rawBody,
    isReply: hasMatrixReplyContent(effectiveContent),
  ).trim();
  return visible.isEmpty ? fallback : visible;
}

Map<dynamic, dynamic> matrixEffectiveMessageContent(
  Map<dynamic, dynamic> content,
) {
  final relatesTo = content['m.relates_to'];
  final replacement = content['m.new_content'];
  if (relatesTo is Map &&
      relatesTo['rel_type'] == 'm.replace' &&
      replacement is Map) {
    return replacement;
  }
  return content;
}

String stripMatrixReplyFallback(String body, {required bool isReply}) {
  if (!isReply) return body;

  final normalized = body.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
  final lines = normalized.split('\n');
  if (lines.isEmpty || !lines.first.startsWith('> ')) return body;

  var index = 0;
  while (index < lines.length && lines[index].startsWith('> ')) {
    index++;
  }
  if (index >= lines.length || lines[index].trim().isNotEmpty) return body;
  while (index < lines.length && lines[index].trim().isEmpty) {
    index++;
  }
  return lines.skip(index).join('\n');
}

String stripMatrixFormattedReplyFallback(String html, {required bool isReply}) {
  if (!isReply || !html.trimLeft().startsWith('<mx-reply')) return html;
  const closingTag = '</mx-reply>';
  final end = html.indexOf(closingTag);
  if (end < 0) return html;
  return html.substring(end + closingTag.length).trimLeft();
}

String matrixAttachmentFileName(
  Event event, {
  String fallback = 'attachment',
}) => matrixAttachmentFileNameFromContent(event.content, fallback: fallback);

String matrixAttachmentFileNameFromContent(
  Map<dynamic, dynamic> content, {
  String fallback = 'attachment',
}) {
  final effectiveContent = matrixEffectiveMessageContent(content);
  final filename = effectiveContent['filename'];
  if (filename is String && filename.trim().isNotEmpty) {
    return filename.trim();
  }
  return matrixVisibleBodyFromContent(effectiveContent, fallback: fallback);
}

String safeMatrixAttachmentFileName(
  Event event, {
  String fallback = 'attachment',
}) => sanitizeAttachmentFileName(
  matrixAttachmentFileName(event, fallback: fallback),
  fallback: fallback,
);

String sanitizeAttachmentFileName(
  String value, {
  String fallback = 'attachment',
}) {
  final pathParts = value.trim().split(RegExp(r'[/\\]'));
  var name = pathParts.isEmpty ? '' : pathParts.last;
  name = name
      .replaceAll(RegExp(r'[\x00-\x1F\x7F]'), '_')
      .replaceAll(RegExp(r'[<>:"|?*]'), '_')
      .trim();
  if (name.isEmpty || name == '.' || name == '..') name = fallback;
  if (name.length > 180) name = name.substring(0, 180);
  return name;
}
