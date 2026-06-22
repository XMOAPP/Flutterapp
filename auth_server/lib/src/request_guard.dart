import 'dart:io';

class RequestRateLimiter {
  RequestRateLimiter({
    this.window = const Duration(minutes: 1),
    this.maxRequestsPerWindow = 60,
  });

  final Duration window;
  final int maxRequestsPerWindow;
  final Map<String, _RateWindow> _windows = <String, _RateWindow>{};

  bool allow(HttpRequest request) {
    final key = '${_clientAddress(request)}:${request.uri.path}';
    final now = DateTime.now().toUtc();
    final current = _windows[key];
    if (current == null || now.difference(current.startedAt) >= window) {
      _windows[key] = _RateWindow(now, 1);
      _removeExpired(now);
      return true;
    }
    if (current.count >= maxRequestsPerWindow) return false;
    current.count += 1;
    return true;
  }

  String _clientAddress(HttpRequest request) {
    final forwarded = request.headers.value('x-forwarded-for');
    if (forwarded != null && forwarded.isNotEmpty) {
      return forwarded.split(',').first.trim();
    }
    return request.connectionInfo?.remoteAddress.address ?? 'unknown';
  }

  void _removeExpired(DateTime now) {
    _windows.removeWhere(
      (_, value) => now.difference(value.startedAt) > window * 2,
    );
  }
}

class _RateWindow {
  _RateWindow(this.startedAt, this.count);
  final DateTime startedAt;
  int count;
}
