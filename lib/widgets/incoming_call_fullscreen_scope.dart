import 'package:flutter/widgets.dart';

import '../services/voip_service.dart';

class IncomingCallFullscreenScope extends StatefulWidget {
  final Widget child;

  const IncomingCallFullscreenScope({
    super.key,
    required this.child,
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
    VoipService().enterFullscreenIncomingCallScope();
  }

  @override
  void dispose() {
    VoipService().exitFullscreenIncomingCallScope();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
