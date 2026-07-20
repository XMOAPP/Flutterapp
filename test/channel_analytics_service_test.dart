import 'package:flutter_test/flutter_test.dart';
import 'package:xmo/services/channel_analytics_service.dart';

void main() {
  group('ChannelAnalyticsSnapshot', () {
    test('parses per-post views, forwards, and average views', () {
      final snapshot = ChannelAnalyticsSnapshot.fromJson({
        'averageViews': 2.5,
        'posts': {
          r'$one': {'views': 3, 'forwards': 2},
          r'$two': {'views': 2, 'forwards': 0},
        },
      });

      expect(snapshot.averageViews, 2.5);
      expect(snapshot.analyticsFor(r'$one').views, 3);
      expect(snapshot.analyticsFor(r'$one').forwards, 2);
      expect(snapshot.analyticsFor(r'$two').views, 2);
    });

    test('returns safe zero values for a post without analytics', () {
      final snapshot = ChannelAnalyticsSnapshot.fromJson(const {});

      expect(snapshot.averageViews, 0);
      expect(snapshot.analyticsFor(r'$missing').views, 0);
      expect(snapshot.analyticsFor(r'$missing').forwards, 0);
    });
  });
}
