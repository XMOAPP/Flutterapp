import 'dart:io';
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
  Uint8List? _selectedVideoThumbnail;
  String? _selectedMediaMimeType;
  String? _selectedMediaFileName;
  StoryMediaType _mediaType = StoryMediaType.text;
  bool _uploading = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _recoverLostStoryPhoto();
    });
  }

  @override
  void dispose() {
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
    required Uint8List videoBytes,
    required String mimeType,
  }) async {
    File? tempVideoFile;
    try {
      if (videoBytes.isEmpty) return null;

      final webThumbnail =
          await web_video.generateVideoThumbnail(videoBytes, mimeType);
      if (webThumbnail != null && webThumbnail.isNotEmpty) {
        return webThumbnail;
      }

      final tempDir = await getTemporaryDirectory();
      tempVideoFile = File(
        '${tempDir.path}/story_thumb_source_${DateTime.now().microsecondsSinceEpoch}${_fileExtensionForMime(mimeType)}',
      );
      await tempVideoFile.writeAsBytes(videoBytes, flush: true);

      return await VideoThumbnail.thumbnailData(
        video: tempVideoFile.path,
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
    final bytes = await pickedFile.readAsBytes();
    if (bytes.isEmpty || !mounted) return;

    final mimeType = pickedFile.mimeType ??
        lookupMimeType(pickedFile.name, headerBytes: bytes) ??
        lookupMimeType(pickedFile.path, headerBytes: bytes) ??
        'image/jpeg';
    final isVideo = mimeType.startsWith('video/');

    final thumbnailBytes = isVideo
        ? await _generateVideoThumbnail(
            videoBytes: bytes,
            mimeType: mimeType,
          )
        : null;
    if (!mounted) return;

    setState(() {
      _selectedMedia = bytes;
      _selectedVideoThumbnail = thumbnailBytes;
      _selectedMediaMimeType = mimeType;
      _selectedMediaFileName = pickedFile.name.isNotEmpty
          ? pickedFile.name
          : '${isVideo ? 'story_video' : 'story_image'}_${DateTime.now().millisecondsSinceEpoch}${isVideo ? _fileExtensionForMime(mimeType) : '.jpg'}';
      _mediaType = isVideo ? StoryMediaType.video : StoryMediaType.image;
    });
  }

  Future<void> _showCameraPicker() async {
    final result = await Navigator.push<CameraCaptureResult>(
      context,
      MaterialPageRoute(builder: (_) => const CameraCaptureScreen()),
    );
    if (!mounted || result == null || result.bytes.isEmpty) return;

    final isVideo = result.type == CameraCaptureMediaType.video;
    final thumbnailBytes = isVideo
        ? await _generateVideoThumbnail(
            videoBytes: result.bytes,
            mimeType: result.mimeType,
          )
        : null;
    if (!mounted) return;

    setState(() {
      _selectedMedia = result.bytes;
      _selectedVideoThumbnail = thumbnailBytes;
      _selectedMediaMimeType = result.mimeType;
      _selectedMediaFileName = result.fileName;
      if (result.caption.trim().isNotEmpty) {
        _captionController.text = result.caption.trim();
      }
      _mediaType = isVideo ? StoryMediaType.video : StoryMediaType.image;
    });
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
    if (_selectedMedia == null && _captionController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please add an image, video, or text'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() => _uploading = true);

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
        mediaType: _mediaType,
        mediaBytes: _selectedMedia,
        mediaMimeType: _selectedMediaMimeType,
        mediaFileName: _selectedMediaFileName,
        thumbnailBytes:
            _mediaType == StoryMediaType.video ? _selectedVideoThumbnail : null,
        caption: _captionController.text.trim().isNotEmpty
            ? _captionController.text.trim()
            : null,
        textContent:
            _selectedMedia == null ? _captionController.text.trim() : null,
        privacy: storyPrivacy,
        customPrivacyList:
            privacySettings.storyAudience == XmoPrivacyAudience.contacts
                ? null
                : privacySettings.storyUserIds,
      );

      final story = await storyProvider.createStory(request);

      if (story != null && mounted) {
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to create story: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _uploading = false);
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
            const Center(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    color: kLimeGreen,
                    strokeWidth: 2,
                  ),
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
            child: _selectedMedia != null
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
                      hintText: _selectedMedia != null
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
                if (_selectedMedia != null)
                  _buildMediaButton(
                    icon: Icons.delete_outline,
                    label: 'Remove',
                    color: Colors.red,
                    onTap: () {
                      setState(() {
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
