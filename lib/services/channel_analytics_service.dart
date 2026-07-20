import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:matrix/matrix.dart';

import '../config/app_config.dart';

class ChannelPostAnalytics {
  const ChannelPostAnalytics({required this.views, required this.forwards});

  factory ChannelPostAnalytics.fromJson(Map<String, dynamic> json) {
    return ChannelPostAnalytics(
      views: (json['views'] as num?)?.toInt() ?? 0,
      forwards: (json['forwards'] as num?)?.toInt() ?? 0,
    );
  }

  final int views;
  final int forwards;
}

class ChannelAnalyticsSnapshot {
  const ChannelAnalyticsSnapshot({
    required this.posts,
    required this.averageViews,
  });

  factory ChannelAnalyticsSnapshot.fromJson(Map<String, dynamic> json) {
    final rawPosts = json['posts'];
    final posts = <String, ChannelPostAnalytics>{};
    if (rawPosts is Map) {
      for (final entry in rawPosts.entries) {
        final value = entry.value;
        if (value is Map) {
          posts[entry.key.toString()] = ChannelPostAnalytics.fromJson(
            value.map((key, item) => MapEntry(key.toString(), item)),
          );
        }
      }
    }
    return ChannelAnalyticsSnapshot(
      posts: posts,
      averageViews: (json['averageViews'] as num?)?.toDouble() ?? 0,
    );
  }

  final Map<String, ChannelPostAnalytics> posts;
  final double averageViews;

  ChannelPostAnalytics analyticsFor(String eventId) =>
      posts[eventId] ?? const ChannelPostAnalytics(views: 0, forwards: 0);
}

class ChannelAnalyticsService {
  ChannelAnalyticsService(
    this._client, {
    http.Client? httpClient,
    String? serverUrl,
  })  : _httpClient = httpClient,
        _serverUrl = serverUrl ?? AppConfig.channelAnalyticsServerUrl;

  final Client _client;
  final http.Client? _httpClient;
  final String _serverUrl;

  Future<void> recordView({
    required String roomId,
    required String eventId,
  }) async {
    await _post('channel/analytics/view', {
      'roomId': roomId,
      'eventId': eventId,
    });
  }

  Future<void> recordForward({
    required String roomId,
    required String eventId,
    required String targetRoomId,
    required String targetEventId,
  }) async {
    await _post('channel/analytics/forward', {
      'roomId': roomId,
      'eventId': eventId,
      'targetRoomId': targetRoomId,
      'targetEventId': targetEventId,
    });
  }

  Future<ChannelAnalyticsSnapshot> getStatistics(
    String roomId, {
    Iterable<String> eventIds = const [],
  }) async {
    final body = await _post('channel/analytics/stats', {
      'roomId': roomId,
      if (eventIds.isNotEmpty) 'eventIds': eventIds.toSet().toList(),
    });
    return ChannelAnalyticsSnapshot.fromJson(body);
  }

  Future<Map<String, dynamic>> _post(
    String path,
    Map<String, dynamic> payload,
  ) async {
    final token = _client.accessToken;
    if (token == null || token.isEmpty) throw StateError('Not signed in');
    final request = (_httpClient?.post ?? http.post)(
      _endpoint(path),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: jsonEncode(payload),
    );
    final response = await request.timeout(const Duration(seconds: 12));
    final decoded = _decode(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(decoded['error']?.toString() ?? 'Analytics unavailable');
    }
    return decoded;
  }

  Uri _endpoint(String path) {
    final trimmed = _serverUrl.trim();
    final normalized = trimmed.endsWith('/')
        ? trimmed.substring(0, trimmed.length - 1)
        : trimmed;
    final base = Uri.parse(normalized);
    return base.replace(path: '${base.path}/$path');
  }

  Map<String, dynamic> _decode(String value) {
    try {
      final decoded = jsonDecode(value);
      if (decoded is Map) {
        return decoded.map((key, item) => MapEntry(key.toString(), item));
      }
    } catch (_) {}
    return const {};
  }
}
