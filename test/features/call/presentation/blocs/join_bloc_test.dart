import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:video_call_app/core/permissions/permission_service.dart';
import 'package:video_call_app/features/call/domain/entities/connection_params.dart';
import 'package:video_call_app/features/call/presentation/blocs/join/join_bloc.dart';

class MockPermissionService extends Mock implements PermissionService {}

void main() {
  late MockPermissionService permissionService;

  setUp(() {
    permissionService = MockPermissionService();
  });

  JoinBloc buildBloc() => JoinBloc(permissionService);

  group('field changes', () {
    blocTest<JoinBloc, JoinState>(
      'update state and reset status',
      build: buildBloc,
      act: (bloc) => bloc
        ..add(const JoinRoomIdChanged('Room-1'))
        ..add(const JoinUserNameChanged('Alice')),
      expect: () => const [
        JoinState(roomId: 'Room-1'),
        JoinState(roomId: 'Room-1', userName: 'Alice'),
      ],
    );
  });

  group('validation', () {
    blocTest<JoinBloc, JoinState>(
      'submit with empty fields fails without requesting permissions',
      build: buildBloc,
      act: (bloc) => bloc.add(const JoinSubmitted()),
      expect: () => const [
        JoinState(
          status: JoinStatus.failure,
          errorMessage: 'Enter a room ID and your name.',
        ),
      ],
      verify: (_) =>
          verifyNever(() => permissionService.requestCallPermissions()),
    );

    blocTest<JoinBloc, JoinState>(
      'submit with whitespace-only fields fails',
      build: buildBloc,
      seed: () => const JoinState(roomId: '   ', userName: '  '),
      act: (bloc) => bloc.add(const JoinSubmitted()),
      expect: () => const [
        JoinState(
          roomId: '   ',
          userName: '  ',
          status: JoinStatus.failure,
          errorMessage: 'Enter a room ID and your name.',
        ),
      ],
    );

    blocTest<JoinBloc, JoinState>(
      'submit with invalid room-id characters fails',
      build: buildBloc,
      seed: () => const JoinState(roomId: 'room 1!', userName: 'Alice'),
      act: (bloc) => bloc.add(const JoinSubmitted()),
      expect: () => const [
        JoinState(
          roomId: 'room 1!',
          userName: 'Alice',
          status: JoinStatus.failure,
          errorMessage:
              'Room ID can only contain letters, numbers, "-" and "_".',
        ),
      ],
      verify: (_) =>
          verifyNever(() => permissionService.requestCallPermissions()),
    );

    blocTest<JoinBloc, JoinState>(
      're-submitting the same invalid input re-emits so feedback re-shows',
      build: buildBloc,
      // Already in a failure state from a prior identical submit.
      seed: () => const JoinState(
        roomId: 'room 1!',
        userName: 'Alice',
        status: JoinStatus.failure,
        errorMessage:
            'Room ID can only contain letters, numbers, "-" and "_".',
      ),
      act: (bloc) => bloc.add(const JoinSubmitted()),
      // Passes through initial so the failure is a distinct, non-deduped state.
      expect: () => const [
        JoinState(roomId: 'room 1!', userName: 'Alice'),
        JoinState(
          roomId: 'room 1!',
          userName: 'Alice',
          status: JoinStatus.failure,
          errorMessage:
              'Room ID can only contain letters, numbers, "-" and "_".',
        ),
      ],
    );
  });

  group('permissions', () {
    blocTest<JoinBloc, JoinState>(
      'granted permissions produce ready with normalized params',
      build: buildBloc,
      setUp: () => when(() => permissionService.requestCallPermissions())
          .thenAnswer((_) async => CallPermissionResult.granted),
      seed: () => const JoinState(roomId: '  My-Room ', userName: '  Alice '),
      act: (bloc) => bloc.add(const JoinSubmitted()),
      expect: () => const [
        JoinState(
          roomId: '  My-Room ',
          userName: '  Alice ',
          status: JoinStatus.requestingPermissions,
        ),
        JoinState(
          roomId: '  My-Room ',
          userName: '  Alice ',
          status: JoinStatus.ready,
          params: ConnectionParams(roomId: 'my-room', userName: 'Alice'),
        ),
      ],
    );

    blocTest<JoinBloc, JoinState>(
      'denied permissions produce permissionDenied',
      build: buildBloc,
      setUp: () => when(() => permissionService.requestCallPermissions())
          .thenAnswer((_) async => CallPermissionResult.denied),
      seed: () => const JoinState(roomId: 'room', userName: 'Alice'),
      act: (bloc) => bloc.add(const JoinSubmitted()),
      expect: () => const [
        JoinState(
          roomId: 'room',
          userName: 'Alice',
          status: JoinStatus.requestingPermissions,
        ),
        JoinState(
          roomId: 'room',
          userName: 'Alice',
          status: JoinStatus.permissionDenied,
          errorMessage:
              'Camera and microphone access are required to join a call.',
        ),
      ],
    );

    blocTest<JoinBloc, JoinState>(
      'permanently denied permissions produce permissionPermanentlyDenied',
      build: buildBloc,
      setUp: () => when(() => permissionService.requestCallPermissions())
          .thenAnswer((_) async => CallPermissionResult.permanentlyDenied),
      seed: () => const JoinState(roomId: 'room', userName: 'Alice'),
      act: (bloc) => bloc.add(const JoinSubmitted()),
      expect: () => const [
        JoinState(
          roomId: 'room',
          userName: 'Alice',
          status: JoinStatus.requestingPermissions,
        ),
        JoinState(
          roomId: 'room',
          userName: 'Alice',
          status: JoinStatus.permissionPermanentlyDenied,
          errorMessage:
              'Camera and microphone access are blocked. Enable them in '
              'Settings to join a call.',
        ),
      ],
    );
  });

  group('reset', () {
    blocTest<JoinBloc, JoinState>(
      'clears status but keeps the entered fields',
      build: buildBloc,
      seed: () => const JoinState(
        roomId: 'room',
        userName: 'Alice',
        status: JoinStatus.ready,
        params: ConnectionParams(roomId: 'room', userName: 'Alice'),
      ),
      act: (bloc) => bloc.add(const JoinReset()),
      expect: () => const [
        JoinState(roomId: 'room', userName: 'Alice'),
      ],
    );
  });
}
