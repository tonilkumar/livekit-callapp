import 'package:get_it/get_it.dart';
import 'package:http/http.dart' as http;

import '../../features/call/data/datasources/livekit_room_data_source.dart';
import '../../features/call/data/datasources/token_service.dart';
import '../../features/call/data/repositories/livekit_call_repository.dart';
import '../../features/call/domain/repositories/call_repository.dart';
import '../../features/call/domain/usecases/connect_to_room.dart';
import '../../features/call/domain/usecases/leave_room.dart';
import '../../features/call/domain/usecases/toggle_camera.dart';
import '../../features/call/domain/usecases/toggle_microphone.dart';
import '../../features/call/domain/usecases/watch_connection_status.dart';
import '../../features/call/domain/usecases/watch_participants.dart';
import '../../features/call/presentation/blocs/call/call_bloc.dart';
import '../../features/call/presentation/blocs/join/join_bloc.dart';
import '../permissions/permission_service.dart';

final sl = GetIt.instance;

void configureDependencies() {
  // Core
  sl.registerLazySingleton(PermissionService.new);
  sl.registerLazySingleton(http.Client.new);

  // Data — the repository is a singleton (one live call at a time) but
  // creates a fresh LiveKit Room per connect.
  sl.registerLazySingleton<TokenService>(() => SandboxTokenService(sl()));
  sl.registerLazySingleton(LiveKitRoomDataSource.new);
  sl.registerLazySingleton<CallRepository>(
    () => LiveKitCallRepository(sl(), sl()),
  );

  // Domain
  sl.registerFactory(() => ConnectToRoom(sl()));
  sl.registerFactory(() => LeaveRoom(sl()));
  sl.registerFactory(() => ToggleMicrophone(sl()));
  sl.registerFactory(() => ToggleCamera(sl()));
  sl.registerFactory(() => WatchConnectionStatus(sl()));
  sl.registerFactory(() => WatchParticipants(sl()));

  // Presentation — factories: a fresh bloc per screen visit.
  sl.registerFactory(() => JoinBloc(sl()));
  sl.registerFactory(
    () => CallBloc(
      connectToRoom: sl(),
      leaveRoom: sl(),
      toggleMicrophone: sl(),
      toggleCamera: sl(),
      watchConnectionStatus: sl(),
      watchParticipants: sl(),
    ),
  );
}
