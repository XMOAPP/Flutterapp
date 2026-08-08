import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' as webrtc;
import 'package:google_fonts/google_fonts.dart';
import 'package:matrix/matrix.dart';

import '../../services/matrix_service.dart';
import '../../services/voip_service.dart';
import '../../theme.dart';
import '../../utils/matrix_identity.dart';
import '../../widgets/story/story_avatar.dart';

class GroupCallScreen extends StatefulWidget {
  final XmoGroupCall groupCall;

  const GroupCallScreen({super.key, required this.groupCall});

  @override
  State<GroupCallScreen> createState() => _GroupCallScreenState();
}

class _GroupCallScreenState extends State<GroupCallScreen> {
  final List<StreamSubscription> _subscriptions = [];
  Timer? _durationTimer;
  Duration _callDuration = Duration.zero;
  bool _leaving = false;
  bool _closingWithoutPip = false;
  bool _speakerOn = false;
  bool _localVideoMirrored = true;
  String? _pinnedVideoUserId;

  XmoGroupCall get _call => widget.groupCall;
  bool get _isVideoCall => _call.type == XmoGroupCallType.video;
  bool get _canEndCall => VoipService().canEndGroupCall(_call);
  bool get _shouldKeepCallInPip =>
      !_closingWithoutPip && !_leaving && _call.state != GroupCallState.ended;

  @override
  void initState() {
    super.initState();
    VoipService().enterFullscreenCallRoute();
    _subscriptions.add(_call.eventStream.listen((_) => _handleCallUpdate()));
    _subscriptions.add(_call.stateStream.listen((_) => _handleCallUpdate()));
    _subscriptions.add(
      _call.streamAddStream.listen((_) => _handleCallUpdate()),
    );
    _subscriptions.add(
      _call.streamRemovedStream.listen((_) => _handleCallUpdate()),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_isVideoCall) {
        _speakerOn = true;
        _enableSpeaker();
      }
      _startDurationTimer();
    });
  }

  @override
  void dispose() {
    _durationTimer?.cancel();
    for (final subscription in _subscriptions) {
      subscription.cancel();
    }
    VoipService().exitFullscreenCallRoute();
    if (_shouldKeepCallInPip) {
      VoipService().minimizeCall();
      VoipService().ensurePipVisibleAfterCallRouteClosed();
    }
    super.dispose();
  }

  void _handleCallUpdate() {
    if (!mounted) return;
    setState(() {});
    _startDurationTimer();

    if (_call.state == GroupCallState.ended && !_leaving) {
      _leaving = true;
      Future.delayed(const Duration(milliseconds: 350), () {
        if (mounted && Navigator.canPop(context)) Navigator.pop(context);
      });
    }
  }

  void _startDurationTimer() {
    if (_durationTimer != null) return;

    void syncDuration() {
      final connectedAt = VoipService().groupCallConnectedAt;
      if (connectedAt == null) {
        if (mounted) setState(() => _callDuration = Duration.zero);
        return;
      }
      final nextDuration = DateTime.now().difference(connectedAt);
      if (mounted) {
        setState(() => _callDuration = nextDuration);
      } else {
        _callDuration = nextDuration;
      }
    }

    syncDuration();
    _durationTimer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => syncDuration(),
    );
  }

  Future<void> _leave() async {
    if (_leaving) return;
    setState(() => _leaving = true);
    try {
      await VoipService().leaveOrEndGroupCall(_call);
      _closingWithoutPip = true;
      if (mounted && Navigator.canPop(context)) Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      setState(() => _leaving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to ${_canEndCall ? 'end' : 'leave'} call: $e'),
        ),
      );
    }
  }

  Future<void> _toggleMic() async {
    await _call.setMicrophoneMuted(!_call.isMicrophoneMuted);
    if (mounted) setState(() {});
  }

  Future<void> _toggleCamera() async {
    await _call.setLocalVideoMuted(!_call.isLocalVideoMuted);
    if (mounted) setState(() {});
  }

  Future<void> _toggleSpeaker() async {
    if (_isVideoCall) return;
    try {
      _speakerOn = !_speakerOn;
      await webrtc.Helper.setSpeakerphoneOn(_speakerOn);
      if (mounted) setState(() {});
    } catch (e) {
      debugPrint('[GroupCallScreen] Speaker toggle failed: $e');
    }
  }

  void _minimizeToPopup() {
    if (!_shouldKeepCallInPip) return;
    VoipService().minimizeCall();
    if (mounted && Navigator.canPop(context)) {
      Navigator.pop(context);
      return;
    }
  }

  void _handleRoutePop() {
    if (_shouldKeepCallInPip) {
      VoipService().minimizeCall();
    }
  }

  void _togglePinVideo(String userId) {
    setState(() {
      _pinnedVideoUserId = _pinnedVideoUserId == userId ? null : userId;
    });
  }

  Future<void> _copyCallLink() async {
    await Clipboard.setData(
      ClipboardData(text: VoipService().groupCallLink(_call.room)),
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('Call link copied')));
  }

  Future<void> _enableSpeaker() async {
    try {
      await webrtc.Helper.setSpeakerphoneOn(true);
    } catch (e) {
      debugPrint('[GroupCallScreen] Speaker enable failed: $e');
    }
  }

  Future<void> _flipCamera() async {
    try {
      final stream = _call.localUserMediaStream?.stream;
      if (stream == null) return;
      final videoTracks = stream.getVideoTracks();
      if (videoTracks.isNotEmpty) {
        await webrtc.Helper.switchCamera(videoTracks.first);
        if (mounted) {
          setState(() => _localVideoMirrored = !_localVideoMirrored);
        }
      }
    } catch (e) {
      debugPrint('[GroupCallScreen] Camera flip failed: $e');
    }
  }

  String _formatDuration(Duration d) {
    final hours = d.inHours;
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    if (hours > 0) return '$hours:$minutes:$seconds';
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    final roomName = MatrixService.cleanName(
      MatrixService().getResolvedDisplayName(_call.room),
    );
    final streams = _call.userMediaStreams.toList();
    final participants = _participantsFor(streams);

    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) _handleRoutePop();
      },
      child: Scaffold(
        backgroundColor: kBlack,
        body: SafeArea(
          child: Stack(
            children: [
              Positioned.fill(
                child: Column(
                  children: [
                    _buildHeader(roomName),
                    Expanded(
                      child: _isVideoCall
                          ? _buildVideoStage(streams)
                          : _buildVoiceStage(participants),
                    ),
                    _buildControls(),
                  ],
                ),
              ),
              Positioned(
                top: 8,
                left: 8,
                child: _topBarButton(
                  icon: Icons.picture_in_picture_alt,
                  onTap: _minimizeToPopup,
                ),
              ),
              Positioned(
                top: 8,
                right: 8,
                child: _topBarButton(icon: Icons.link, onTap: _copyCallLink),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<_GroupCallParticipant> _participantsFor(
    List<WrappedMediaStream> streams,
  ) {
    final byUserId = <String, _GroupCallParticipant>{};
    for (final stream in streams) {
      final user = _call.room.getParticipants().where(
        (u) => u.id == stream.userId,
      );
      byUserId[stream.userId] = _GroupCallParticipant.fromStream(
        stream,
        user: user.isEmpty ? null : user.first,
      );
    }
    for (final user in _call.participants) {
      byUserId.putIfAbsent(
        user.id,
        () => _GroupCallParticipant(
          userId: user.id,
          name: MatrixIdentity.displayName(
            userId: user.id,
            candidate: user.displayName,
          ),
          avatarUrl: user.avatarUrl?.toString(),
        ),
      );
    }
    return byUserId.values.toList()..sort((a, b) {
      if (a.userId == _call.activeSpeaker) return -1;
      if (b.userId == _call.activeSpeaker) return 1;
      if (a.isLocal) return -1;
      if (b.isLocal) return 1;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
  }

  Widget _buildHeader(String roomName) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(66, 12, 66, 10),
      child: Column(
        children: [
          Text(
            roomName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              color: kWhite,
              fontSize: 20,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${_call.participants.length} participants  ${_formatDuration(_callDuration)}',
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              color: kLightGrey,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _topBarButton({required IconData icon, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.black.withValues(alpha: 0.55),
        ),
        child: Icon(icon, color: kWhite, size: 20),
      ),
    );
  }

  Widget _buildVideoStage(List<WrappedMediaStream> streams) {
    if (streams.isEmpty) {
      return _buildEmptyState(Icons.videocam_outlined, 'Connecting video...');
    }

    final activeStream = _activeVideoStream(streams);
    final secondaryStreams = streams
        .where((stream) => stream.userId != activeStream.userId)
        .toList();

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final stripHeight = secondaryStreams.isEmpty
              ? 0.0
              : constraints.maxHeight < 520
              ? 112.0
              : 138.0;

          return Column(
            children: [
              Expanded(
                child: _VideoParticipantTile(
                  key: ValueKey(_streamTileKey(activeStream)),
                  stream: activeStream,
                  avatarUrl: _avatarUrlForStream(activeStream),
                  large: true,
                  pinned: _pinnedVideoUserId == activeStream.userId,
                  localVideoMirrored: _localVideoMirrored,
                  onPin: () => _togglePinVideo(activeStream.userId),
                ),
              ),
              if (secondaryStreams.isNotEmpty) ...[
                const SizedBox(height: 10),
                SizedBox(
                  height: stripHeight,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: secondaryStreams.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 8),
                    itemBuilder: (context, index) {
                      final stream = secondaryStreams[index];
                      return SizedBox(
                        width: stripHeight * 0.78,
                        child: _VideoParticipantTile(
                          key: ValueKey(_streamTileKey(stream)),
                          stream: stream,
                          avatarUrl: _avatarUrlForStream(stream),
                          pinned: _pinnedVideoUserId == stream.userId,
                          localVideoMirrored: _localVideoMirrored,
                          onPin: () => _togglePinVideo(stream.userId),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }

  WrappedMediaStream _activeVideoStream(List<WrappedMediaStream> streams) {
    final pinnedUserId = _pinnedVideoUserId;
    if (pinnedUserId != null) {
      final pinned = streams.where((stream) => stream.userId == pinnedUserId);
      if (pinned.isNotEmpty) return pinned.first;
      _pinnedVideoUserId = null;
    }
    final activeSpeaker = _call.activeSpeaker;
    if (activeSpeaker != null) {
      final activeMatches = streams.where(
        (stream) => stream.userId == activeSpeaker,
      );
      if (activeMatches.isNotEmpty) return activeMatches.first;
    }
    final remoteWithVideo = streams.where(
      (stream) => !stream.isLocal() && !stream.isVideoMuted(),
    );
    if (remoteWithVideo.isNotEmpty) return remoteWithVideo.first;
    return streams.first;
  }

  String _streamTileKey(WrappedMediaStream stream) {
    return '${stream.userId}:${stream.stream?.id ?? 'empty'}';
  }

  String? _avatarUrlForStream(WrappedMediaStream stream) {
    final users = _call.room.getParticipants().where(
      (user) => user.id == stream.userId,
    );
    if (users.isEmpty) return null;
    return users.first.avatarUrl?.toString();
  }

  Widget _buildVoiceStage(List<_GroupCallParticipant> participants) {
    if (participants.isEmpty) {
      return _buildEmptyState(Icons.call_outlined, 'Connecting audio...');
    }

    final activeParticipant = participants.firstWhere(
      (participant) => participant.userId == _call.activeSpeaker,
      orElse: () => participants.first,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxHeight < 520;
        return Column(
          children: [
            SizedBox(height: compact ? 10 : 24),
            _ActiveVoiceParticipant(
              participant: activeParticipant,
              active: activeParticipant.userId == _call.activeSpeaker,
            ),
            SizedBox(height: compact ? 18 : 30),
            Expanded(
              child: _ParticipantGrid(
                participants: participants,
                activeUserId: _call.activeSpeaker,
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildEmptyState(IconData icon, String label) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: kLimeGreen, size: 46),
          const SizedBox(height: 12),
          Text(
            label,
            style: GoogleFonts.inter(
              color: kLightGrey,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildControls() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
      child: SizedBox(
        width: 520,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _CallControlButton(
              icon: _call.isMicrophoneMuted ? Icons.mic_off : Icons.mic,
              label: _call.isMicrophoneMuted ? 'Muted' : 'Mute',
              color: kWhite.withValues(alpha: 0.10),
              onTap: _toggleMic,
            ),
            if (_isVideoCall)
              _CallControlButton(
                icon: Icons.cameraswitch,
                label: 'Rotate',
                color: kWhite.withValues(alpha: 0.10),
                onTap: _flipCamera,
              )
            else
              _CallControlButton(
                icon: _speakerOn ? Icons.volume_up : Icons.volume_off,
                label: 'Speaker',
                color: _speakerOn
                    ? kWhite.withValues(alpha: 0.18)
                    : kWhite.withValues(alpha: 0.10),
                onTap: _toggleSpeaker,
              ),
            if (_isVideoCall)
              _CallControlButton(
                icon: _call.isLocalVideoMuted
                    ? Icons.videocam_off
                    : Icons.videocam,
                label: _call.isLocalVideoMuted ? 'Camera off' : 'Camera',
                color: kWhite.withValues(alpha: 0.10),
                onTap: _toggleCamera,
              ),
            _CallControlButton(
              icon: Icons.call_end,
              label: _canEndCall ? 'End' : 'Leave',
              color: Colors.red,
              destructive: true,
              disabled: _leaving,
              onTap: _leave,
            ),
          ],
        ),
      ),
    );
  }
}

class _GroupCallParticipant {
  final String userId;
  final String name;
  final String? avatarUrl;
  final bool muted;
  final bool isLocal;

  const _GroupCallParticipant({
    required this.userId,
    required this.name,
    this.avatarUrl,
    this.muted = false,
    this.isLocal = false,
  });

  factory _GroupCallParticipant.fromStream(
    WrappedMediaStream stream, {
    User? user,
  }) {
    return _GroupCallParticipant(
      userId: stream.userId,
      name: stream.isLocal()
          ? 'You'
          : MatrixIdentity.displayName(
              userId: stream.userId,
              candidate: stream.displayName ?? user?.displayName,
            ),
      avatarUrl: user?.avatarUrl?.toString(),
      muted: stream.isAudioMuted(),
      isLocal: stream.isLocal(),
    );
  }
}

class _VideoParticipantTile extends StatelessWidget {
  final WrappedMediaStream stream;
  final String? avatarUrl;
  final bool large;
  final bool pinned;
  final bool localVideoMirrored;
  final VoidCallback onPin;

  const _VideoParticipantTile({
    super.key,
    required this.stream,
    this.avatarUrl,
    required this.pinned,
    required this.localVideoMirrored,
    required this.onPin,
    this.large = false,
  });

  @override
  Widget build(BuildContext context) {
    final rtcRenderer = VoipService().rendererFor(stream);
    final showVideo =
        rtcRenderer != null && stream.stream != null && !stream.isVideoMuted();
    final name = MatrixIdentity.displayName(
      userId: stream.userId,
      candidate: stream.displayName,
    );

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1B1B1D),
        borderRadius: BorderRadius.circular(large ? 20 : 14),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          Positioned.fill(
            child: showVideo
                ? webrtc.RTCVideoView(
                    key: ValueKey(stream.stream!.id),
                    rtcRenderer,
                    mirror: stream.isLocal() && localVideoMirrored,
                    objectFit:
                        webrtc.RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                  )
                : _ParticipantAvatar(name: name, avatarUrl: avatarUrl),
          ),
          Positioned(
            left: 10,
            right: 10,
            bottom: 10,
            child: Row(
              children: [
                if (stream.isAudioMuted())
                  const Padding(
                    padding: EdgeInsets.only(right: 6),
                    child: Icon(Icons.mic_off, color: kWhite, size: 16),
                  ),
                Expanded(
                  child: Text(
                    stream.isLocal() ? 'You' : name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(
                      color: kWhite,
                      fontSize: large ? 14 : 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Positioned(
            top: 8,
            right: 8,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (stream.isAudioMuted())
                  Container(
                    width: 26,
                    height: 26,
                    margin: const EdgeInsets.only(right: 6),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.58),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.mic_off, color: kWhite, size: 15),
                  ),
                GestureDetector(
                  onTap: onPin,
                  child: Container(
                    width: 26,
                    height: 26,
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.58),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      pinned ? Icons.push_pin : Icons.push_pin_outlined,
                      color: pinned ? kLimeGreen : kWhite,
                      size: 15,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ActiveVoiceParticipant extends StatelessWidget {
  final _GroupCallParticipant participant;
  final bool active;

  const _ActiveVoiceParticipant({
    required this.participant,
    required this.active,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 148,
          height: 148,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: active ? Border.all(color: kLimeGreen, width: 1.6) : null,
          ),
          child: ClipOval(
            child: _ParticipantAvatar(
              name: participant.name,
              avatarUrl: participant.avatarUrl,
              fontSize: 56,
            ),
          ),
        ),
        const SizedBox(height: 14),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (participant.muted)
              const Padding(
                padding: EdgeInsets.only(right: 6),
                child: Icon(Icons.mic_off, color: kLightGrey, size: 17),
              ),
            Text(
              participant.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.inter(
                color: kWhite,
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _ParticipantGrid extends StatelessWidget {
  final List<_GroupCallParticipant> participants;
  final String? activeUserId;

  const _ParticipantGrid({
    required this.participants,
    required this.activeUserId,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 520 ? 4 : 3;
        final itemWidth =
            (constraints.maxWidth - ((columns - 1) * 10)) / columns;
        return SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 4),
          child: Wrap(
            alignment: WrapAlignment.center,
            spacing: 10,
            runSpacing: 12,
            children: participants
                .map(
                  (participant) => SizedBox(
                    width: itemWidth.clamp(92.0, 132.0),
                    child: _VoiceParticipantTile(
                      participant: participant,
                      active: participant.userId == activeUserId,
                    ),
                  ),
                )
                .toList(),
          ),
        );
      },
    );
  }
}

class _VoiceParticipantTile extends StatelessWidget {
  final _GroupCallParticipant participant;
  final bool active;

  const _VoiceParticipantTile({
    required this.participant,
    required this.active,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF151517),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ClipOval(
            child: SizedBox(
              width: 54,
              height: 54,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: _ParticipantAvatar(
                      name: participant.name,
                      avatarUrl: participant.avatarUrl,
                      fontSize: 22,
                    ),
                  ),
                  if (participant.muted)
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: Container(
                        width: 18,
                        height: 18,
                        decoration: const BoxDecoration(
                          color: kBlack,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.mic_off,
                          color: kLimeGreen,
                          size: 12,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (participant.muted)
                const Padding(
                  padding: EdgeInsets.only(right: 4),
                  child: Icon(Icons.mic_off, color: kLightGrey, size: 14),
                ),
              Flexible(
                child: Text(
                  participant.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                    color: kWhite,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ParticipantAvatar extends StatelessWidget {
  final String name;
  final String? avatarUrl;
  final double fontSize;

  const _ParticipantAvatar({
    required this.name,
    this.avatarUrl,
    this.fontSize = 34,
  });

  @override
  Widget build(BuildContext context) {
    final size = fontSize * 2.42;
    return StoryAvatar(
      userName: name,
      avatarUrl: avatarUrl,
      backgroundColor: const Color(0xFF242426),
      fallbackIcon: null,
      size: size,
    );
  }
}

class _CallControlButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final bool destructive;
  final bool disabled;
  final Future<void> Function() onTap;

  const _CallControlButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
    this.destructive = false,
    this.disabled = false,
  });

  @override
  Widget build(BuildContext context) {
    final isDestructive = destructive || color == Colors.red;

    return Opacity(
      opacity: disabled ? 0.55 : 1,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isDestructive ? null : color,
              gradient: isDestructive
                  ? const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Color(0xFFFF6961),
                        Color(0xFFFF3B30),
                        Color(0xFFC21D1D),
                      ],
                    )
                  : null,
            ),
            child: Material(
              color: Colors.transparent,
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: disabled ? null : onTap,
                child: SizedBox(
                  width: 58,
                  height: 58,
                  child: Icon(icon, color: kWhite, size: 26),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: GoogleFonts.inter(
              color: isDestructive ? Colors.red : kWhite,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
