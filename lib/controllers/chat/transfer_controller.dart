import 'package:flutter/foundation.dart';

enum ChatTransferKind { upload, download }

enum ChatTransferStatus { queued, running, completed, failed, cancelled }

class ChatTransferSnapshot {
  const ChatTransferSnapshot({
    required this.id,
    required this.kind,
    required this.status,
    this.fileName,
    this.bytesTransferred = 0,
    this.totalBytes,
    this.error,
  });

  final String id;
  final ChatTransferKind kind;
  final ChatTransferStatus status;
  final String? fileName;
  final int bytesTransferred;
  final int? totalBytes;
  final Object? error;

  double? get progress {
    final total = totalBytes;
    if (total == null || total <= 0) return null;
    return (bytesTransferred / total).clamp(0.0, 1.0).toDouble();
  }

  ChatTransferSnapshot copyWith({
    ChatTransferStatus? status,
    String? fileName,
    int? bytesTransferred,
    int? totalBytes,
    Object? error,
  }) {
    return ChatTransferSnapshot(
      id: id,
      kind: kind,
      status: status ?? this.status,
      fileName: fileName ?? this.fileName,
      bytesTransferred: bytesTransferred ?? this.bytesTransferred,
      totalBytes: totalBytes ?? this.totalBytes,
      error: error ?? this.error,
    );
  }
}

class ChatTransferController extends ChangeNotifier {
  final Map<String, ChatTransferSnapshot> _transfers = {};

  List<ChatTransferSnapshot> get transfers =>
      List.unmodifiable(_transfers.values);

  ChatTransferSnapshot? byId(String id) => _transfers[id];

  void upsert(ChatTransferSnapshot snapshot) {
    _transfers[snapshot.id] = snapshot;
    notifyListeners();
  }

  void remove(String id) {
    if (_transfers.remove(id) != null) {
      notifyListeners();
    }
  }

  void clearCompleted() {
    final before = _transfers.length;
    _transfers.removeWhere(
      (_, transfer) =>
          transfer.status == ChatTransferStatus.completed ||
          transfer.status == ChatTransferStatus.cancelled,
    );
    if (_transfers.length != before) {
      notifyListeners();
    }
  }
}
