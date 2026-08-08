import 'package:flutter/material.dart';

final RouteObserver<ModalRoute<dynamic>> xmoRouteObserver =
    RouteObserver<ModalRoute<dynamic>>();

class VisibleChatRouteService {
  static final VisibleChatRouteService instance = VisibleChatRouteService._();
  VisibleChatRouteService._();

  final ValueNotifier<String?> roomId = ValueNotifier<String?>(null);
  Object? _visibleOwner;

  void show(Object owner, String? value) {
    _visibleOwner = owner;
    if (roomId.value != value) roomId.value = value;
  }

  void hide(Object owner) {
    if (!identical(_visibleOwner, owner)) return;
    _visibleOwner = null;
    roomId.value = null;
  }
}
