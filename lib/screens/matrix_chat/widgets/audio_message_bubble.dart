// ignore_for_file: experimental_member_use

import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:just_audio/just_audio.dart';
import 'package:matrix/matrix.dart';
import '../../../theme.dart';
import 'voice_waveform.dart';

class AudioMessageBubble extends StatefulWidget {
  final Event event;
  final bool isMe;
  final String time;
  final Future<MatrixFile> Function(Event) downloadAttachment;
  final Widget Function(Event) buildMessageStatus;

  const AudioMessageBubble({
    super.key,
    required this.event,
    required this.isMe,
    required this.time,
    required this.downloadAttachment,
    required this.buildMessageStatus,
  });

  @override
  State<AudioMessageBubble> createState() => _AudioMessageBubbleState();
}

class _AudioMessageBubbleState extends State<AudioMessageBubble> {
  static _AudioMessageBubbleState? _activeBubble;

  final AudioPlayer _player = AudioPlayer();
  bool _loading = false;
  bool _prepared = false;
  Future<void>? _prepareFuture;
  StreamSubscription<PlayerState>? _playerStateSub;
  double? _scrubProgress;
  int _seekRequestId = 0;

  @override
  void initState() {
    super.initState();
    _playerStateSub = _player.playerStateStream.listen((state) {
      if (state.processingState == ProcessingState.completed) {
        _player.seek(Duration.zero);
        _player.pause();
      }
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    if (_activeBubble == this) {
      _activeBubble = null;
    }
    _playerStateSub?.cancel();
    _player.dispose();
    super.dispose();
  }

  Future<void> _togglePlayback() async {
    if (_player.playing) {
      await _player.pause();
      if (_activeBubble == this) {
        _activeBubble = null;
      }
      return;
    }

    await _prepareAudio();
    await _stopOtherActiveBubble();
    _activeBubble = this;
    await _player.play();
  }

  Future<void> _stopOtherActiveBubble() async {
    final active = _activeBubble;
    if (active == null || active == this || !active.mounted) return;
    await active._stopForNewAudio();
  }

  Future<void> _stopForNewAudio() async {
    try {
      await _player.pause();
    } finally {
      if (_activeBubble == this) {
        _activeBubble = null;
      }
      if (mounted) setState(() {});
    }
  }

  Future<void> _prepareAudio() {
    if (_prepared) return Future.value();
    return _prepareFuture ??= _loadAudio();
  }

  Future<void> _loadAudio() async {
    if (mounted) {
      setState(() => _loading = true);
    }
    try {
      final matrixFile = await widget.downloadAttachment(widget.event);
      await _player.setAudioSource(
        _BytesAudioSource(
          matrixFile.bytes,
          contentType: _mimeType,
        ),
      );
      _prepared = true;
    } finally {
      _prepareFuture = null;
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _seekToProgress(double progress) async {
    final normalizedProgress = progress.clamp(0.0, 1.0);
    final requestId = ++_seekRequestId;
    if (mounted) {
      setState(() => _scrubProgress = normalizedProgress);
    }

    try {
      await _prepareAudio();
      if (requestId != _seekRequestId) return;

      final duration = _player.duration ?? _eventDuration;
      if (duration.inMilliseconds <= 0) return;
      final target = Duration(
        milliseconds: (duration.inMilliseconds * normalizedProgress).round(),
      );
      await _player.seek(target);
    } catch (_) {
      // Playback preparation already reports failures through the existing
      // attachment download path. Keep waveform seeking non-disruptive.
    } finally {
      if (mounted && requestId == _seekRequestId) {
        setState(() => _scrubProgress = null);
      }
    }
  }

  String get _mimeType {
    final info = widget.event.content['info'];
    if (info is Map && info['mimetype'] is String) {
      return info['mimetype'] as String;
    }
    return 'audio/mp4';
  }

  Duration get _eventDuration {
    final info = widget.event.content['info'];
    final raw = info is Map ? info['duration'] : null;
    final millis =
        raw is num ? raw.toInt() : int.tryParse(raw?.toString() ?? '');
    return Duration(milliseconds: millis ?? 0);
  }

  String _format(Duration duration) {
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    final duration = _player.duration ?? _eventDuration;
    final isPlaying = _player.playing;
    final accent = widget.isMe ? kLimeGreen : const Color(0xFF3B82F6);
    final inactive = widget.isMe
        ? kLimeGreen.withValues(alpha: 0.25)
        : Colors.white.withValues(alpha: 0.22);
    final screenWidth = MediaQuery.sizeOf(context).width;
    final maxBubbleWidth = math.min(
      330.0,
      math.max(160.0, screenWidth * 0.78),
    );
    final minBubbleWidth = math.min(280.0, maxBubbleWidth);
    final textScale = MediaQuery.textScalerOf(context).scale(1);
    final bubbleHeight = 58.0 + math.max(0.0, textScale - 1.0) * 12.0;

    return StreamBuilder<Duration>(
      stream: _player.positionStream,
      initialData: _player.position,
      builder: (context, snapshot) {
        final position = snapshot.data ?? Duration.zero;
        final playbackProgress = duration.inMilliseconds <= 0
            ? 0.0
            : position.inMilliseconds / duration.inMilliseconds;
        final progress = _scrubProgress ?? playbackProgress;
        final displayedPosition = _scrubProgress == null
            ? position
            : Duration(
                milliseconds:
                    (duration.inMilliseconds * _scrubProgress!).round(),
              );

        return ConstrainedBox(
          constraints: BoxConstraints(
            minWidth: minBubbleWidth,
            maxWidth: maxBubbleWidth,
          ),
          child: SizedBox(
            height: bubbleHeight,
            child: Stack(
              children: [
                Align(
                  alignment: Alignment.topCenter,
                  child: SizedBox(
                    height: 48,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        GestureDetector(
                          onTap: _loading ? null : _togglePlayback,
                          child: Container(
                            width: 42,
                            height: 42,
                            decoration: BoxDecoration(
                              color: accent,
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: accent.withValues(alpha: 0.25),
                                  blurRadius: 12,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: _loading
                                ? const Padding(
                                    padding: EdgeInsets.all(13),
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: kBlack,
                                    ),
                                  )
                                : Icon(
                                    isPlaying
                                        ? Icons.pause_rounded
                                        : Icons.play_arrow_rounded,
                                    color: widget.isMe ? kBlack : kWhite,
                                    size: 27,
                                  ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: VoiceWaveform(
                            color: accent,
                            inactiveColor: inactive,
                            progress: progress,
                            height: 30,
                            onSeek: _seekToProgress,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Align(
                  alignment: Alignment.bottomCenter,
                  child: Row(
                    children: [
                      const SizedBox(width: 54),
                      Text(
                        _format(
                          _scrubProgress != null
                              ? displayedPosition
                              : (_prepared || isPlaying ? position : duration),
                        ),
                        style: GoogleFonts.inter(
                          color: widget.isMe
                              ? kLimeGreen.withValues(alpha: 0.75)
                              : kLightGrey,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        widget.time,
                        style: GoogleFonts.inter(
                          color: widget.isMe
                              ? kLimeGreen.withValues(alpha: 0.6)
                              : kLightGrey,
                          fontSize: 10,
                        ),
                      ),
                      if (widget.isMe) ...[
                        const SizedBox(width: 4),
                        widget.buildMessageStatus(widget.event),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _BytesAudioSource extends StreamAudioSource {
  final Uint8List bytes;
  final String contentType;

  _BytesAudioSource(this.bytes, {required this.contentType});

  @override
  Future<StreamAudioResponse> request([int? start, int? end]) async {
    start ??= 0;
    end ??= bytes.length;
    return StreamAudioResponse(
      sourceLength: bytes.length,
      contentLength: end - start,
      offset: start,
      stream: Stream.value(bytes.sublist(start, end)),
      contentType: contentType,
    );
  }
}
