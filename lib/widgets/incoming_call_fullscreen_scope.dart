import 'package:flutter/widgets.dart';

import '../services/voip_service.dart';

class IncomingCallFullscreenScope extends StatefulWidget {
  final Widget child;
  final String? roomId;

  const IncomingCallFullscreenScope({
    super.key,
    required this.child,
    this.roomId,
  });

  @override
  State<IncomingCallFullscreenScope> createState() =>
      _IncomingCallFullscreenScopeState();
}

class _IncomingCallFullscreenScopeState
    extends State<IncomingCallFullscreenScope> {
  @override
  void initState() {
    super.initState();
    VoipService().enterFullscreenIncomingCallScope(roomId: widget.roomId);
  }

  @override
  void dispose() {
    VoipService().exitFullscreenIncomingCallScope(roomId: widget.roomId);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
