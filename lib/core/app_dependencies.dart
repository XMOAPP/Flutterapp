import 'package:flutter/widgets.dart';

import '../repositories/auth_session_repository.dart';
import '../repositories/group_channel_repository.dart';
import '../repositories/media_repository.dart';
import '../repositories/push_repository.dart';
import '../repositories/room_repository.dart';
import '../services/matrix_service.dart';

class AppDependencies {
  AppDependencies._({
    required this.matrixService,
    required this.auth,
    required this.rooms,
    required this.media,
    required this.push,
    required this.groups,
  });

  factory AppDependencies.from(MatrixService matrixService) {
    return AppDependencies._(
      matrixService: matrixService,
      auth: AuthSessionRepository(matrixService),
      rooms: RoomRepository(matrixService),
      media: MediaRepository(matrixService),
      push: PushRepository(matrixService),
      groups: GroupChannelRepository(matrixService),
    );
  }

  final MatrixService matrixService;
  final AuthSessionRepository auth;
  final RoomRepository rooms;
  final MediaRepository media;
  final PushRepository push;
  final GroupChannelRepository groups;
}

class AppDependenciesScope extends InheritedWidget {
  const AppDependenciesScope({
    super.key,
    required this.dependencies,
    required super.child,
  });

  final AppDependencies dependencies;

  static AppDependencies? maybeOf(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<AppDependenciesScope>()
        ?.dependencies;
  }

  static AppDependencies of(BuildContext context) {
    final dependencies = maybeOf(context);
    assert(dependencies != null, 'AppDependenciesScope not found');
    return dependencies!;
  }

  @override
  bool updateShouldNotify(AppDependenciesScope oldWidget) {
    return dependencies != oldWidget.dependencies;
  }
}
