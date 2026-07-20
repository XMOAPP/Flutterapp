import 'dart:convert';
import 'dart:typed_data';

const String xmoStreamContentKey = 'xmo_stream';

const int _expectedChunkKeyBytes = 32;
const int _expectedChunkIvBytes = 16;
const int _expectedChunkHashBytes = 32;
const int _maxManifestJsonBytes = 128 * 1024;
const int _maxMimeTypeLength = 128;
const int _maxQualityNameLength = 32;
const int _maxQualityCount = 4;
const int _maxChunkCountPerQuality = 4096;
const int _maxChunkUrlLength = 4096;
const int _maxChunkSizeBytes = 8 * 1024 * 1024;
const int _maxStreamSizeBytes = 4 * 1024 * 1024 * 1024;
final RegExp _qualityNamePattern = RegExp(r'^[a-zA-Z0-9_-]+$');

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
    _validateManifestEncodedSize(json);
    final version = _requiredInt(json, 'version');
    if (version != supportedVersion) {
      throw XmoStreamManifestException(
        'Unsupported xmo_stream version: $version.',
      );
    }

    final mimeType = _requiredString(json, 'mime_type');
    _validateMimeType(mimeType, 'mime_type');
    final size = _requiredPositiveInt(json, 'size');
    final chunkSize = _requiredPositiveInt(json, 'chunk_size');
    _validateSizeLimit(size, 'size');
    _validateChunkSize(chunkSize, 'chunk_size');
    final durationMs = _optionalNonNegativeInt(json, 'duration_ms');
    final rawQualities = json['qualities'];
    if (rawQualities is! Map || rawQualities.isEmpty) {
      throw const XmoStreamManifestException(
        'xmo_stream qualities must be a non-empty object.',
      );
    }
    if (rawQualities.length > _maxQualityCount) {
      throw const XmoStreamManifestException(
        'xmo_stream can contain at most $_maxQualityCount qualities.',
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
      if (name.length > _maxQualityNameLength ||
          !_qualityNamePattern.hasMatch(name)) {
        throw XmoStreamManifestException(
          'xmo_stream quality "$name" has an invalid name.',
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
    if (!qualities.containsKey('source')) {
      throw const XmoStreamManifestException(
        'xmo_stream must include a source quality.',
      );
    }

    _validateQualitySizes(
      qualities,
      inheritedSize: size,
      inheritedChunkSize: chunkSize,
    );
    _validateChunkUniqueness(qualities);

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
    if (size != null) _validateSizeLimit(size, '$name size');
    if (chunkSize != null) _validateChunkSize(chunkSize, '$name chunk_size');
    if (mimeType != null) _validateMimeType(mimeType, '$name mime_type');
    if (rawChunks.length > _maxChunkCountPerQuality) {
      throw XmoStreamManifestException(
        'xmo_stream quality "$name" has too many chunks.',
      );
    }

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
    if (url.length > _maxChunkUrlLength || uri == null) {
      throw const XmoStreamManifestException(
        'xmo_stream chunk url is invalid.',
      );
    }
    if (uri.isScheme('mxc')) {
      if (uri.host.isEmpty || uri.pathSegments.isEmpty) {
        throw const XmoStreamManifestException(
          'xmo_stream mxc chunk url is invalid.',
        );
      }
    } else if (uri.isScheme('https')) {
      if (uri.host.isEmpty) {
        throw const XmoStreamManifestException(
          'xmo_stream https chunk url is invalid.',
        );
      }
    } else {
      throw const XmoStreamManifestException(
        'xmo_stream chunk url must be mxc or https.',
      );
    }

    final key = _requiredString(json, 'key');
    final iv = _requiredString(json, 'iv');
    final sha256 = _requiredString(json, 'sha256');
    _requireDecodedLength(key, _expectedChunkKeyBytes, 'chunk key');
    _requireDecodedLength(iv, _expectedChunkIvBytes, 'chunk iv');
    _requireDecodedLength(sha256, _expectedChunkHashBytes, 'chunk sha256');

    return XmoStreamChunk(
      index: index,
      url: url,
      key: key,
      iv: iv,
      sha256: sha256,
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

void _validateManifestEncodedSize(Map<dynamic, dynamic> json) {
  try {
    final bytes = utf8.encode(jsonEncode(json)).length;
    if (bytes > _maxManifestJsonBytes) {
      throw const XmoStreamManifestException(
        'xmo_stream manifest is too large.',
      );
    }
  } on JsonUnsupportedObjectError {
    throw const XmoStreamManifestException(
      'xmo_stream manifest contains unsupported values.',
    );
  }
}

void _validateMimeType(String mimeType, String field) {
  if (mimeType.length > _maxMimeTypeLength ||
      mimeType.contains(RegExp(r'[\r\n]')) ||
      !mimeType.contains('/')) {
    throw XmoStreamManifestException('xmo_stream $field is invalid.');
  }
}

void _validateSizeLimit(int value, String field) {
  if (value > _maxStreamSizeBytes) {
    throw XmoStreamManifestException('xmo_stream $field is too large.');
  }
}

void _validateChunkSize(int value, String field) {
  if (value > _maxChunkSizeBytes) {
    throw XmoStreamManifestException('xmo_stream $field is too large.');
  }
}

void _validateQualitySizes(
  Map<String, XmoStreamQuality> qualities, {
  required int inheritedSize,
  required int inheritedChunkSize,
}) {
  for (final entry in qualities.entries) {
    final quality = entry.value;
    final size = quality.size ?? inheritedSize;
    final chunkSize = quality.chunkSize ?? inheritedChunkSize;
    final expectedChunks = (size + chunkSize - 1) ~/ chunkSize;
    if (quality.chunks.length != expectedChunks) {
      throw XmoStreamManifestException(
        'xmo_stream quality "${entry.key}" chunk count does not match its size.',
      );
    }
  }
}

void _validateChunkUniqueness(Map<String, XmoStreamQuality> qualities) {
  final seenKeyIvPairs = <String>{};
  for (final quality in qualities.values) {
    final seenUrls = <String>{};
    for (final chunk in quality.chunks) {
      if (!seenUrls.add(chunk.url)) {
        throw const XmoStreamManifestException(
          'xmo_stream contains duplicate chunk URLs.',
        );
      }
      if (!seenKeyIvPairs.add('${chunk.key}:${chunk.iv}')) {
        throw const XmoStreamManifestException(
          'xmo_stream contains reused chunk key and IV.',
        );
      }
    }
  }
}

void _requireDecodedLength(String value, int expectedLength, String field) {
  final decoded = _decodeBase64Like(value);
  if (decoded == null || decoded.length != expectedLength) {
    throw XmoStreamManifestException('xmo_stream $field is invalid.');
  }
}

Uint8List? _decodeBase64Like(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty ||
      !RegExp(r'^[A-Za-z0-9+/_-]+={0,2}$').hasMatch(trimmed)) {
    return null;
  }
  final normalized = trimmed.replaceAll('-', '+').replaceAll('_', '/');
  final padding = (4 - normalized.length % 4) % 4;
  try {
    return Uint8List.fromList(base64.decode(normalized + ('=' * padding)));
  } on FormatException {
    return null;
  }
}
