const String xmoStreamContentKey = 'xmo_stream';

class XmoStreamManifestException implements Exception {
  const XmoStreamManifestException(this.message);

  final String message;

  @override
  String toString() => message;
}

class XmoStreamManifest {
  static const int supportedVersion = 1;

  final int version;
  final String mimeType;
  final int size;
  final int chunkSize;
  final int? durationMs;
  final Map<String, XmoStreamQuality> qualities;

  const XmoStreamManifest({
    required this.version,
    required this.mimeType,
    required this.size,
    required this.chunkSize,
    this.durationMs,
    required this.qualities,
  });

  XmoStreamQuality? quality(String name) => qualities[name];

  XmoStreamQuality? get sourceQuality => quality('source');

  String resolveQuality(XmoStreamQualityMode mode) {
    switch (mode) {
      case XmoStreamQualityMode.dataSaver:
        return _firstAvailable(['240p', '480p', 'source']);
      case XmoStreamQualityMode.highQuality:
        return _firstAvailable(['480p', 'source', '240p']);
      case XmoStreamQualityMode.original:
        return _firstAvailable(['source', '480p', '240p']);
      case XmoStreamQualityMode.auto:
        return _firstAvailable(['480p', '240p', 'source']);
    }
  }

  String _firstAvailable(List<String> preferred) {
    for (final name in preferred) {
      if (qualities.containsKey(name)) return name;
    }
    return qualities.keys.first;
  }

  static XmoStreamManifest? fromEventContent(Map<dynamic, dynamic> content) {
    final raw = content[xmoStreamContentKey];
    if (raw == null) return null;
    if (raw is! Map) {
      throw const XmoStreamManifestException('xmo_stream must be an object.');
    }
    return XmoStreamManifest.fromJson(raw);
  }

  factory XmoStreamManifest.fromJson(Map<dynamic, dynamic> json) {
    final version = _requiredInt(json, 'version');
    if (version != supportedVersion) {
      throw XmoStreamManifestException(
        'Unsupported xmo_stream version: $version.',
      );
    }

    final mimeType = _requiredString(json, 'mime_type');
    final size = _requiredPositiveInt(json, 'size');
    final chunkSize = _requiredPositiveInt(json, 'chunk_size');
    final durationMs = _optionalNonNegativeInt(json, 'duration_ms');
    final rawQualities = json['qualities'];
    if (rawQualities is! Map || rawQualities.isEmpty) {
      throw const XmoStreamManifestException(
        'xmo_stream qualities must be a non-empty object.',
      );
    }

    final qualities = <String, XmoStreamQuality>{};
    for (final entry in rawQualities.entries) {
      final name = entry.key?.toString().trim() ?? '';
      if (name.isEmpty) {
        throw const XmoStreamManifestException(
          'xmo_stream quality name cannot be empty.',
        );
      }
      final value = entry.value;
      if (value is! Map) {
        throw XmoStreamManifestException(
          'xmo_stream quality "$name" must be an object.',
        );
      }
      qualities[name] = XmoStreamQuality.fromJson(value, name: name);
    }

    return XmoStreamManifest(
      version: version,
      mimeType: mimeType,
      size: size,
      chunkSize: chunkSize,
      durationMs: durationMs,
      qualities: Map.unmodifiable(qualities),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'version': version,
      'mime_type': mimeType,
      'size': size,
      'chunk_size': chunkSize,
      if (durationMs != null) 'duration_ms': durationMs,
      'qualities': {
        for (final entry in qualities.entries) entry.key: entry.value.toJson(),
      },
    };
  }
}

class XmoStreamQuality {
  final int? size;
  final int? chunkSize;
  final String? mimeType;
  final List<XmoStreamChunk> chunks;

  const XmoStreamQuality({
    this.size,
    this.chunkSize,
    this.mimeType,
    required this.chunks,
  });

  factory XmoStreamQuality.fromJson(
    Map<dynamic, dynamic> json, {
    required String name,
  }) {
    final rawChunks = json['chunks'];
    if (rawChunks is! List || rawChunks.isEmpty) {
      throw XmoStreamManifestException(
        'xmo_stream quality "$name" chunks must be a non-empty list.',
      );
    }
    final size = _optionalPositiveInt(json, 'size');
    final chunkSize = _optionalPositiveInt(json, 'chunk_size');
    final mimeType = _optionalString(json, 'mime_type');

    final chunks = <XmoStreamChunk>[];
    final seenIndexes = <int>{};
    for (final rawChunk in rawChunks) {
      if (rawChunk is! Map) {
        throw XmoStreamManifestException(
          'xmo_stream quality "$name" chunk must be an object.',
        );
      }
      final chunk = XmoStreamChunk.fromJson(rawChunk);
      if (!seenIndexes.add(chunk.index)) {
        throw XmoStreamManifestException(
          'xmo_stream quality "$name" has duplicate chunk index ${chunk.index}.',
        );
      }
      chunks.add(chunk);
    }

    chunks.sort((a, b) => a.index.compareTo(b.index));
    for (var i = 0; i < chunks.length; i++) {
      if (chunks[i].index != i) {
        throw XmoStreamManifestException(
          'xmo_stream quality "$name" chunk indexes must start at 0 and be contiguous.',
        );
      }
    }

    return XmoStreamQuality(
      size: size,
      chunkSize: chunkSize,
      mimeType: mimeType,
      chunks: List.unmodifiable(chunks),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (size != null) 'size': size,
      if (chunkSize != null) 'chunk_size': chunkSize,
      if (mimeType != null) 'mime_type': mimeType,
      'chunks': chunks.map((chunk) => chunk.toJson()).toList(),
    };
  }
}

enum XmoStreamQualityMode {
  auto,
  dataSaver,
  highQuality,
  original;

  static XmoStreamQualityMode fromName(String name) {
    final normalized = name.trim().toLowerCase().replaceAll('-', '_');
    switch (normalized) {
      case 'data_saver':
      case 'datasaver':
      case 'data saver':
        return XmoStreamQualityMode.dataSaver;
      case 'high':
      case 'high_quality':
      case 'highquality':
      case 'high quality':
        return XmoStreamQualityMode.highQuality;
      case 'original':
      case 'source':
        return XmoStreamQualityMode.original;
      case 'auto':
      default:
        return XmoStreamQualityMode.auto;
    }
  }
}

class XmoStreamChunk {
  final int index;
  final String url;
  final String key;
  final String iv;
  final String sha256;

  const XmoStreamChunk({
    required this.index,
    required this.url,
    required this.key,
    required this.iv,
    required this.sha256,
  });

  factory XmoStreamChunk.fromJson(Map<dynamic, dynamic> json) {
    final index = _requiredInt(json, 'index');
    if (index < 0) {
      throw const XmoStreamManifestException(
        'xmo_stream chunk index cannot be negative.',
      );
    }

    final url = _requiredString(json, 'url');
    final uri = Uri.tryParse(url);
    if (uri == null ||
        !(uri.isScheme('mxc') ||
            uri.isScheme('https') ||
            uri.isScheme('http'))) {
      throw const XmoStreamManifestException(
        'xmo_stream chunk url must be mxc, https, or http.',
      );
    }

    return XmoStreamChunk(
      index: index,
      url: url,
      key: _requiredString(json, 'key'),
      iv: _requiredString(json, 'iv'),
      sha256: _requiredString(json, 'sha256'),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'index': index,
      'url': url,
      'key': key,
      'iv': iv,
      'sha256': sha256,
    };
  }
}

int _requiredInt(Map<dynamic, dynamic> json, String key) {
  final value = json[key];
  if (value is int) return value;
  if (value is num && value % 1 == 0) return value.toInt();
  throw XmoStreamManifestException('xmo_stream $key must be an integer.');
}

int _requiredPositiveInt(Map<dynamic, dynamic> json, String key) {
  final value = _requiredInt(json, key);
  if (value <= 0) {
    throw XmoStreamManifestException('xmo_stream $key must be positive.');
  }
  return value;
}

int? _optionalNonNegativeInt(Map<dynamic, dynamic> json, String key) {
  if (!json.containsKey(key) || json[key] == null) return null;
  final value = _requiredInt(json, key);
  if (value < 0) {
    throw XmoStreamManifestException(
      'xmo_stream $key cannot be negative.',
    );
  }
  return value;
}

int? _optionalPositiveInt(Map<dynamic, dynamic> json, String key) {
  if (!json.containsKey(key) || json[key] == null) return null;
  final value = _requiredInt(json, key);
  if (value <= 0) {
    throw XmoStreamManifestException('xmo_stream $key must be positive.');
  }
  return value;
}

String _requiredString(Map<dynamic, dynamic> json, String key) {
  final value = json[key];
  if (value is String && value.trim().isNotEmpty) return value.trim();
  throw XmoStreamManifestException(
    'xmo_stream $key must be a non-empty string.',
  );
}

String? _optionalString(Map<dynamic, dynamic> json, String key) {
  if (!json.containsKey(key) || json[key] == null) return null;
  final value = json[key];
  if (value is String && value.trim().isNotEmpty) return value.trim();
  throw XmoStreamManifestException(
    'xmo_stream $key must be a non-empty string.',
  );
}
