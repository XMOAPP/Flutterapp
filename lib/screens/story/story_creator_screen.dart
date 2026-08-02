import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mime/mime.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:video_thumbnail/video_thumbnail.dart';
import '../../theme.dart';
import '../../models/story_models.dart';
import '../../providers/matrix_provider.dart';
import '../../providers/story_provider.dart';
import '../../services/privacy_service.dart';
import '../../services/story_service.dart';
import '../../widgets/story/story_video_player.dart';
import '../camera_capture_screen.dart';
import '../web_video_view_stub.dart'
    if (dart.library.js_interop) '../web_video_view.dart' as web_video;

/// Story Creator Screen - Create image/video/text stories
class StoryCreatorScreen extends StatefulWidget {
  const StoryCreatorScreen({super.key});

  @override
  State<StoryCreatorScreen> createState() => _StoryCreatorScreenState();
}

class _StoryCreatorScreenState extends State<StoryCreatorScreen> {
  final _captionController = TextEditingController();
  final _imagePicker = ImagePicker();

  Uint8List? _selectedMedia;
  String? _selectedMediaFilePath;
  int? _selectedMediaSizeBytes;
  bool _ownsSelectedMediaFile = false;
  Uint8List? _selectedVideoThumbnail;
  String? _selectedMediaMimeType;
  String? _selectedMediaFileName;
  StoryMediaType _mediaType = StoryMediaType.text;
  bool _uploading = false;
  StoryCreationProgress? _creationProgress;
  StoryCreationCancellationToken? _cancellationToken;
  late String _clientRequestId;

  @override
  void initState() {
    super.initState();
    _clientRequestId = _generateClientRequestId();
    _captionController.addListener(_handleDraftTextChanged);
    unawaited(_cleanupStaleStoryDrafts());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _recoverLostStoryPhoto();
    });
  }

  @override
  void dispose() {
    _cancellationToken?.cancel();
    _captionController.removeListener(_handleDraftTextChanged);
    _deleteOwnedSelectedMedia();
    _captionController.dispose();
    super.dispose();
  }

  Future<void> _pickGalleryMedia() async {
    try {
      final pickedFile = await _imagePicker.pickMedia(
        maxWidth: 1080,
        maxHeight: 1920,
        imageQuality: 85,
      );

      if (pickedFile != null) {
        await _setPickedGalleryMedia(pickedFile);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to pick media: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<Uint8List?> _generateVideoThumbnail({
    Uint8List? videoBytes,
    String? videoFilePath,
    required String mimeType,
  }) async {
    File? tempVideoFile;
    try {
      if ((videoBytes == null || videoBytes.isEmpty) &&
          (videoFilePath == null || videoFilePath.isEmpty)) {
        return null;
      }

      if (videoBytes != null && videoBytes.isNotEmpty) {
        final webThumbnail =
            await web_video.generateVideoThumbnail(videoBytes, mimeType);
        if (webThumbnail != null && webThumbnail.isNotEmpty) {
          return webThumbnail;
        }
      }

      var thumbnailSource = videoFilePath;
      if (thumbnailSource == null && videoBytes != null) {
        final tempDir = await getTemporaryDirectory();
        tempVideoFile = File(
          '${tempDir.path}/story_thumb_source_${DateTime.now().microsecondsSinceEpoch}${_fileExtensionForMime(mimeType)}',
        );
        await tempVideoFile.writeAsBytes(videoBytes, flush: true);
        thumbnailSource = tempVideoFile.path;
      }

      return await VideoThumbnail.thumbnailData(
        video: thumbnailSource!,
        imageFormat: ImageFormat.JPEG,
        maxWidth: 720,
        timeMs: 1000,
        quality: 75,
      );
    } catch (_) {
      return null;
    } finally {
      try {
        if (tempVideoFile != null && await tempVideoFile.exists()) {
          await tempVideoFile.delete();
        }
      } catch (_) {
        // Temporary source cleanup is best-effort.
      }
    }
  }

  Future<XFile?> _retrieveLostPickedImage() async {
    try {
      final response = await _imagePicker.retrieveLostData();
      if (response.isEmpty ||
          response.files == null ||
          response.files!.isEmpty) {
        return null;
      }
      return response.files!.first;
    } catch (_) {
      return null;
    }
  }

  Future<void> _recoverLostStoryPhoto() async {
    final pickedFile = await _retrieveLostPickedImage();
    if (!mounted || pickedFile == null) return;
    await _setPickedImage(pickedFile, fallbackPrefix: 'story_photo');
  }

  Future<void> _setPickedImage(
    XFile pickedFile, {
    String fallbackPrefix = 'story_image',
  }) async {
    final bytes = await pickedFile.readAsBytes();
    if (bytes.isEmpty || !mounted) return;

    setState(() {
      _resetPublishIdentity();
      _replaceSelectedFile();
      _selectedMedia = bytes;
      _selectedVideoThumbnail = null;
      _selectedMediaMimeType = pickedFile.mimeType ??
          lookupMimeType(pickedFile.name, headerBytes: bytes) ??
          lookupMimeType(pickedFile.path, headerBytes: bytes) ??
          'image/jpeg';
      _selectedMediaFileName = pickedFile.name.isNotEmpty
          ? pickedFile.name
          : '${fallbackPrefix}_${DateTime.now().millisecondsSinceEpoch}.jpg';
      _mediaType = StoryMediaType.image;
    });
  }

  Future<void> _setPickedGalleryMedia(XFile pickedFile) async {
    final mimeType = pickedFile.mimeType ??
        lookupMimeType(pickedFile.name) ??
        lookupMimeType(pickedFile.path) ??
        'image/jpeg';
    final isVideo = mimeType.startsWith('video/');

    if (!isVideo) {
      await _setPickedImage(pickedFile);
      return;
    }

    final stagedFile = await _stageVideoFile(
      pickedFile.path,
      mimeType: mimeType,
    );
    if (stagedFile == null) return;
    final thumbnailBytes = await _generateVideoThumbnail(
      videoFilePath: stagedFile.path,
      mimeType: mimeType,
    );
    if (!mounted) {
      await _deleteFile(stagedFile.path);
      return;
    }

    setState(() {
      _resetPublishIdentity();
      _replaceSelectedFile();
      _selectedMedia = null;
      _selectedMediaFilePath = stagedFile.path;
      _selectedMediaSizeBytes = stagedFile.lengthSync();
      _ownsSelectedMediaFile = true;
      _selectedVideoThumbnail = thumbnailBytes;
      _selectedMediaMimeType = mimeType;
      _selectedMediaFileName = pickedFile.name.isNotEmpty
          ? pickedFile.name
          : '${isVideo ? 'story_video' : 'story_image'}_${DateTime.now().millisecondsSinceEpoch}${isVideo ? _fileExtensionForMime(mimeType) : '.jpg'}';
      _mediaType = StoryMediaType.video;
    });
  }

  Future<void> _showCameraPicker() async {
    final result = await Navigator.push<CameraCaptureResult>(
      context,
      MaterialPageRoute(
        builder: (_) => const CameraCaptureScreen(returnVideoFile: true),
      ),
    );
    if (!mounted || result == null) return;

    final isVideo = result.type == CameraCaptureMediaType.video;
    File? stagedVideo;
    if (isVideo && result.filePath != null) {
      stagedVideo = await _stageVideoFile(
        result.filePath!,
        mimeType: result.mimeType,
      );
      if (stagedVideo == null) return;
    }
    final resultBytes = result.bytes;
    if (!isVideo && resultBytes.isEmpty) return;
    final thumbnailBytes = isVideo
        ? await _generateVideoThumbnail(
            videoFilePath: stagedVideo?.path,
            videoBytes: resultBytes,
            mimeType: result.mimeType,
          )
        : null;
    if (!mounted) {
      if (stagedVideo != null) await _deleteFile(stagedVideo.path);
      return;
    }

    setState(() {
      _resetPublishIdentity();
      _replaceSelectedFile();
      _selectedMedia = isVideo ? null : resultBytes;
      _selectedMediaFilePath = stagedVideo?.path;
      _selectedMediaSizeBytes = stagedVideo?.lengthSync();
      _ownsSelectedMediaFile = stagedVideo != null;
      _selectedVideoThumbnail = thumbnailBytes;
      _selectedMediaMimeType = result.mimeType;
      _selectedMediaFileName = result.fileName;
      if (result.caption.trim().isNotEmpty) {
        _captionController.text = result.caption.trim();
      }
      _mediaType = isVideo ? StoryMediaType.video : StoryMediaType.image;
    });
  }

  Future<File?> _stageVideoFile(
    String sourcePath, {
    required String mimeType,
  }) async {
    try {
      final source = File(sourcePath);
      if (!await source.exists() || await source.length() == 0) return null;
      final tempDir = await getTemporaryDirectory();
      final draftDir = Directory('${tempDir.path}/xmo_story_drafts');
      await draftDir.create(recursive: true);
      final destination = File(
        '${draftDir.path}/story_${DateTime.now().microsecondsSinceEpoch}${_fileExtensionForMime(mimeType)}',
      );
      return source.copy(destination.path);
    } catch (_) {
      return null;
    }
  }

  void _replaceSelectedFile() {
    final oldPath = _selectedMediaFilePath;
    final shouldDelete = _ownsSelectedMediaFile;
    _selectedMediaFilePath = null;
    _selectedMediaSizeBytes = null;
    _ownsSelectedMediaFile = false;
    if (shouldDelete && oldPath != null) {
      unawaited(_deleteFile(oldPath));
    }
  }

  void _handleDraftTextChanged() {
    if (!_uploading) _resetPublishIdentity();
  }

  void _resetPublishIdentity() {
    _clientRequestId = _generateClientRequestId();
  }

  String _generateClientRequestId() {
    final random = Random.secure();
    final randomPart = List<int>.generate(
      4,
      (_) => random.nextInt(0x100000000),
    ).map((value) => value.toRadixString(16).padLeft(8, '0')).join();
    return 'story_${DateTime.now().microsecondsSinceEpoch}_$randomPart';
  }

  void _deleteOwnedSelectedMedia() {
    _replaceSelectedFile();
  }

  Future<void> _deleteFile(String path) async {
    try {
      final file = File(path);
      if (await file.exists()) await file.delete();
    } catch (_) {
      // Draft cleanup is best-effort.
    }
  }

  Future<void> _cleanupStaleStoryDrafts() async {
    try {
      final tempDir = await getTemporaryDirectory();
      final draftDir = Directory('${tempDir.path}/xmo_story_drafts');
      if (!await draftDir.exists()) return;
      final cutoff = DateTime.now().subtract(const Duration(days: 1));
      await for (final entity in draftDir.list()) {
        if (entity is! File) continue;
        try {
          final modified = await entity.lastModified();
          if (modified.isBefore(cutoff)) await entity.delete();
        } catch (_) {
          // Continue cleaning the remaining files.
        }
      }
    } catch (_) {
      // Startup cleanup must never block Story creation.
    }
  }

  String _fileExtensionForMime(String mimeType) {
    switch (mimeType.toLowerCase()) {
      case 'video/quicktime':
        return '.mov';
      case 'video/webm':
        return '.webm';
      case 'video/3gpp':
        return '.3gp';
      case 'video/x-m4v':
        return '.m4v';
      default:
        return '.mp4';
    }
  }

  Future<void> _createStory() async {
    if (_selectedMedia == null &&
        _selectedMediaFilePath == null &&
        _captionController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please add an image, video, or text'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final cancellationToken = StoryCreationCancellationToken();
    setState(() {
      _uploading = true;
      _creationProgress = const StoryCreationProgress(
        phase: StoryCreationPhase.preparing,
      );
      _cancellationToken = cancellationToken;
    });

    try {
      final storyProvider = context.read<StoryProvider>();
      final privacySettings = await PrivacyService(
        context.read<MatrixProvider>().service,
      ).loadSettings();
      final storyPrivacy = switch (privacySettings.storyAudience) {
        XmoPrivacyAudience.contacts => StoryPrivacy.contacts,
        XmoPrivacyAudience.onlySelected => StoryPrivacy.custom,
        XmoPrivacyAudience.hideSelected => StoryPrivacy.contactsExcept,
      };

      final request = CreateStoryRequest(
        clientRequestId: _clientRequestId,
        mediaType: _mediaType,
        mediaBytes: _selectedMedia,
        mediaFilePath: _selectedMediaFilePath,
        mediaSizeBytes: _selectedMediaSizeBytes,
        mediaMimeType: _selectedMediaMimeType,
        mediaFileName: _selectedMediaFileName,
        thumbnailBytes:
            _mediaType == StoryMediaType.video ? _selectedVideoThumbnail : null,
        caption: _captionController.text.trim().isNotEmpty
            ? _captionController.text.trim()
            : null,
        textContent: _selectedMedia == null && _selectedMediaFilePath == null
            ? _captionController.text.trim()
            : null,
        privacy: storyPrivacy,
        customPrivacyList:
            privacySettings.storyAudience == XmoPrivacyAudience.contacts
                ? null
                : privacySettings.storyUserIds,
      );

      final story = await storyProvider.createStory(
        request,
        cancellationToken: cancellationToken,
        onProgress: (progress) {
          if (mounted) setState(() => _creationProgress = progress);
        },
      );

      if (story != null && mounted) {
        _deleteOwnedSelectedMedia();
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Story posted!'),
            backgroundColor: kLimeGreen,
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        final message =
            e is StoryValidationException || e is StoryUploadException
                ? e.toString()
                : 'Could not post story. Please try again.';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _uploading = false;
          _creationProgress = null;
          _cancellationToken = null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBlack,
      appBar: AppBar(
        backgroundColor: kBlack,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close, color: kWhite),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Create Story',
          style: GoogleFonts.inter(
            color: kWhite,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
        actions: [
          if (_uploading)
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Row(
                  children: [
                    SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        value: _creationProgress?.fraction,
                        color: kLimeGreen,
                        strokeWidth: 2,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Cancel upload',
                      onPressed: () => _cancellationToken?.cancel(),
                      icon: const Icon(Icons.close, color: kWhite),
                    ),
                  ],
                ),
              ),
            )
          else
            TextButton(
              onPressed: _createStory,
              child: Text(
                'Post',
                style: GoogleFonts.inter(
                  color: kLimeGreen,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
        ],
      ),
      body: Column(
        children: [
          // Preview area
          Expanded(
            child: _selectedMedia != null || _selectedMediaFilePath != null
                ? _buildMediaPreview()
                : _buildTextPreview(),
          ),

          // Caption input
          Container(
            padding: const EdgeInsets.all(14),
            decoration: const BoxDecoration(
              color: kDarkerGrey,
              border: Border(
                top: BorderSide(color: kMediumGrey, width: 1),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _captionController,
                    style: GoogleFonts.inter(color: kWhite, fontSize: 14),
                    decoration: InputDecoration(
                      hintText: _selectedMedia != null ||
                              _selectedMediaFilePath != null
                          ? 'Add a caption...'
                          : 'Type your story...',
                      hintStyle: GoogleFonts.inter(
                        color: kLightGrey,
                        fontSize: 14,
                      ),
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.zero,
                    ),
                    maxLines: 3,
                    minLines: 1,
                  ),
                ),
              ],
            ),
          ),

          // Media picker buttons
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: const BoxDecoration(
              color: kDarkerGrey,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildMediaButton(
                  icon: Icons.photo_library,
                  label: 'Gallery',
                  onTap: _pickGalleryMedia,
                ),
                _buildMediaButton(
                  icon: Icons.camera_alt,
                  label: 'Camera',
                  onTap: _showCameraPicker,
                ),
                if (_selectedMedia != null || _selectedMediaFilePath != null)
                  _buildMediaButton(
                    icon: Icons.delete_outline,
                    label: 'Remove',
                    color: Colors.red,
                    onTap: () {
                      setState(() {
                        _resetPublishIdentity();
                        _replaceSelectedFile();
                        _selectedMedia = null;
                        _selectedVideoThumbnail = null;
                        _selectedMediaMimeType = null;
                        _selectedMediaFileName = null;
                        _mediaType = StoryMediaType.text;
                      });
                    },
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMediaPreview() {
    return Container(
      color: kBlack,
      child: Center(
        child: _mediaType == StoryMediaType.image
            ? Image.memory(
                _selectedMedia!,
                fit: BoxFit.contain,
              )
            : _selectedMediaFilePath != null
                ? StoryVideoPlayer.file(
                    key: ValueKey(_selectedMediaFilePath),
                    filePath: _selectedMediaFilePath!,
                    mimeType: _selectedMediaMimeType ?? 'video/mp4',
                  )
                : StoryVideoPlayer.bytes(
                    key: ValueKey(_selectedMedia),
                    bytes: _selectedMedia!,
                    mimeType: _selectedMediaMimeType ?? 'video/mp4',
                  ),
      ),
    );
  }

  Widget _buildTextPreview() {
    return Container(
      color: kDarkerGrey,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            _captionController.text.isEmpty
                ? 'Type your story or add media'
                : _captionController.text,
            style: GoogleFonts.inter(
              color: kWhite,
              fontSize: 20,
              fontWeight: FontWeight.w500,
            ),
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }

  Widget _buildMediaButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    Color? color,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              color: color ?? kWhite,
              size: 26,
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: GoogleFonts.inter(
                color: color ?? kWhite,
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
