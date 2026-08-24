class RateLimitDecision {
  const RateLimitDecision({
    required this.allowed,
    required this.remaining,
    required this.retryAfter,
  });

  final bool allowed;
  final int remaining;
  final Duration retryAfter;
}

class _RateLimitBucket {
  _RateLimitBucket(this.windowStart, this.count);

  DateTime windowStart;
  int count;
}

class InMemoryRateLimiter {
  InMemoryRateLimiter({required this.maxRequests, required this.window});

  final int maxRequests;
  final Duration window;
  final Map<String, _RateLimitBucket> _buckets = {};

  RateLimitDecision check(String key) {
    final now = DateTime.now().toUtc();
    final bucket = _buckets[key];
    if (bucket == null || now.difference(bucket.windowStart) >= window) {
      _buckets[key] = _RateLimitBucket(now, 1);
      return RateLimitDecision(
        allowed: true,
        remaining: maxRequests - 1,
        retryAfter: Duration.zero,
      );
    }

    bucket.count += 1;
    final allowed = bucket.count <= maxRequests;
    final retryAfter = window - now.difference(bucket.windowStart);
    return RateLimitDecision(
      allowed: allowed,
      remaining: allowed ? maxRequests - bucket.count : 0,
      retryAfter: retryAfter,
    );
  }

  void clearExpired() {
    final now = DateTime.now().toUtc();
    _buckets.removeWhere(
      (_, bucket) => now.difference(bucket.windowStart) >= window,
    );
  }
}
