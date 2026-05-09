import 'package:hive_flutter/hive_flutter.dart';

class AppSettingsService {
  static const String boxName = 'xmo_app_settings';

  static const String notificationsEnabledKey = 'notifications_enabled';
  static const String readReceiptsEnabledKey = 'read_receipts_enabled';
  static const String typingIndicatorsEnabledKey = 'typing_indicators_enabled';
  static const String autoDownloadMediaKey = 'auto_download_media';
  static const String defaultChatFilterKey = 'default_chat_filter';

  Future<Box> _box() async {
    if (Hive.isBoxOpen(boxName)) return Hive.box(boxName);
    return Hive.openBox(boxName);
  }

  Future<AppSettings> load() async {
    final box = await _box();
    return AppSettings(
      notificationsEnabled:
          box.get(notificationsEnabledKey, defaultValue: true) as bool,
      readReceiptsEnabled:
          box.get(readReceiptsEnabledKey, defaultValue: true) as bool,
      typingIndicatorsEnabled:
          box.get(typingIndicatorsEnabledKey, defaultValue: true) as bool,
      autoDownloadMedia:
          box.get(autoDownloadMediaKey, defaultValue: true) as bool,
      defaultChatFilter:
          box.get(defaultChatFilterKey, defaultValue: 'all') as String,
    );
  }

  Future<void> save(AppSettings settings) async {
    final box = await _box();
    await box.put(notificationsEnabledKey, settings.notificationsEnabled);
    await box.put(readReceiptsEnabledKey, settings.readReceiptsEnabled);
    await box.put(typingIndicatorsEnabledKey, settings.typingIndicatorsEnabled);
    await box.put(autoDownloadMediaKey, settings.autoDownloadMedia);
    await box.put(defaultChatFilterKey, settings.defaultChatFilter);
  }

  Future<int> clearMediaCache() async {
    if (!Hive.isBoxOpen('xmo_media_cache')) return 0;
    final box = Hive.box('xmo_media_cache');
    final count = box.length;
    await box.clear();
    return count;
  }
}

class AppSettings {
  final bool notificationsEnabled;
  final bool readReceiptsEnabled;
  final bool typingIndicatorsEnabled;
  final bool autoDownloadMedia;
  final String defaultChatFilter;

  const AppSettings({
    required this.notificationsEnabled,
    required this.readReceiptsEnabled,
    required this.typingIndicatorsEnabled,
    required this.autoDownloadMedia,
    required this.defaultChatFilter,
  });

  AppSettings copyWith({
    bool? notificationsEnabled,
    bool? readReceiptsEnabled,
    bool? typingIndicatorsEnabled,
    bool? autoDownloadMedia,
    String? defaultChatFilter,
  }) {
    return AppSettings(
      notificationsEnabled:
          notificationsEnabled ?? this.notificationsEnabled,
      readReceiptsEnabled: readReceiptsEnabled ?? this.readReceiptsEnabled,
      typingIndicatorsEnabled:
          typingIndicatorsEnabled ?? this.typingIndicatorsEnabled,
      autoDownloadMedia: autoDownloadMedia ?? this.autoDownloadMedia,
      defaultChatFilter: defaultChatFilter ?? this.defaultChatFilter,
    );
  }
}
