import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:video_call_app/core/error/failures.dart';
import 'package:video_call_app/features/call/domain/entities/connection_params.dart';
import 'package:video_call_app/features/call/domain/entities/connection_status.dart';
import 'package:video_call_app/features/call/domain/entities/participant.dart';
import 'package:video_call_app/features/call/domain/usecases/connect_to_room.dart';
import 'package:video_call_app/features/call/domain/usecases/leave_room.dart';
import 'package:video_call_app/features/call/domain/usecases/toggle_camera.dart';
import 'package:video_call_app/features/call/domain/usecases/toggle_microphone.dart';
import 'package:video_call_app/features/call/domain/usecases/watch_connection_status.dart';
import 'package:video_call_app/features/call/domain/usecases/watch_participants.dart';
import 'package:video_call_app/features/call/presentation/blocs/call/call_bloc.dart';

class MockConnectToRoom extends Mock implements ConnectToRoom {}

class MockLeaveRoom extends Mock implements LeaveRoom {}

class MockToggleMicrophone extends Mock implements ToggleMicrophone {}

class MockToggleCamera extends Mock implements ToggleCamera {}

class MockWatchConnectionStatus extends Mock implements WatchConnectionStatus {}

class MockWatchParticipants extends Mock implements WatchParticipants {}

const params = ConnectionParams(roomId: 'room', userName: 'Alice');

Participant buildParticipant({
  required bool isLocal,
  String sid = 'sid-local',
  String name = 'Alice',
  bool mic = true,
  bool cam = true,
  DateTime? joinedAt,
}) {
  return Participant(
    sid: sid,
    identity: '$name-ab12',
    displayName: name,
    isLocal: isLocal,
    isMicEnabled: mic,
    isCameraEnabled: cam,
    isSpeaking: false,
    joinedAt: joinedAt ?? DateTime(2026, 1, 1),
  );
}

void main() {
  late MockConnectToRoom connectToRoom;
  late MockLeaveRoom leaveRoom;
  late MockToggleMicrophone toggleMicrophone;
  late MockToggleCamera toggleCamera;
  late MockWatchConnectionStatus watchConnectionStatus;
  late MockWatchParticipants watchParticipants;
  late StreamController<ConnectionStatus> statusController;
  late StreamController<List<Participant>> participantsController;

  setUpAll(() {
    registerFallbackValue(params);
  });

  setUp(() {
    connectToRoom = MockConnectToRoom();
    leaveRoom = MockLeaveRoom();
    toggleMicrophone = MockToggleMicrophone();
    toggleCamera = MockToggleCamera();
    watchConnectionStatus = MockWatchConnectionStatus();
    watchParticipants = MockWatchParticipants();
    statusController = StreamController<ConnectionStatus>.broadcast();
    participantsController = StreamController<List<Participant>>.broadcast();

    when(() => watchConnectionStatus.call())
        .thenAnswer((_) => statusController.stream);
    when(() => watchParticipants.call())
        .thenAnswer((_) => participantsController.stream);
    when(() => connectToRoom.call(any())).thenAnswer((_) async {});
    when(() => leaveRoom.call()).thenAnswer((_) async {});
  });

  tearDown(() async {
    await statusController.close();
    await participantsController.close();
  });

  CallBloc buildBloc() => CallBloc(
        connectToRoom: connectToRoom,
        leaveRoom: leaveRoom,
        toggleMicrophone: toggleMicrophone,
        toggleCamera: toggleCamera,
        watchConnectionStatus: watchConnectionStatus,
        watchParticipants: watchParticipants,
      );

  group('CallStarted', () {
    blocTest<CallBloc, CallState>(
      'emits connecting, then connected when the status stream reports it',
      build: buildBloc,
      act: (bloc) async {
        bloc.add(const CallStarted(params));
        await Future<void>.delayed(Duration.zero);
        statusController.add(ConnectionStatus.connected);
      },
      wait: const Duration(milliseconds: 50),
      expect: () => const [
        CallState(status: CallStatus.connecting),
        CallState(status: CallStatus.connected),
      ],
      verify: (_) => verify(() => connectToRoom.call(params)).called(1),
    );

    blocTest<CallBloc, CallState>(
      'emits error with the failure message when connect throws',
      build: buildBloc,
      setUp: () => when(() => connectToRoom.call(any()))
          .thenThrow(const TokenConfigFailure('LiveKit is not configured.')),
      act: (bloc) => bloc.add(const CallStarted(params)),
      wait: const Duration(milliseconds: 50),
      expect: () => const [
        CallState(status: CallStatus.connecting),
        CallState(
          status: CallStatus.error,
          errorMessage: 'LiveKit is not configured.',
        ),
      ],
    );

    blocTest<CallBloc, CallState>(
      'a trailing disconnected event does not overwrite an error state',
      build: buildBloc,
      setUp: () => when(() => connectToRoom.call(any()))
          .thenThrow(const ConnectionFailure('boom')),
      act: (bloc) async {
        bloc.add(const CallStarted(params));
        await Future<void>.delayed(Duration.zero);
        statusController.add(ConnectionStatus.disconnected);
      },
      wait: const Duration(milliseconds: 50),
      expect: () => const [
        CallState(status: CallStatus.connecting),
        CallState(status: CallStatus.error, errorMessage: 'boom'),
      ],
    );

    blocTest<CallBloc, CallState>(
      'remote drop maps failed status to an error state',
      build: buildBloc,
      act: (bloc) async {
        bloc.add(const CallStarted(params));
        await Future<void>.delayed(Duration.zero);
        statusController.add(ConnectionStatus.connected);
        statusController.add(ConnectionStatus.failed);
      },
      wait: const Duration(milliseconds: 50),
      expect: () => const [
        CallState(status: CallStatus.connecting),
        CallState(status: CallStatus.connected),
        CallState(status: CallStatus.error, errorMessage: 'Connection lost.'),
      ],
    );
  });

  group('participants', () {
    blocTest<CallBloc, CallState>(
      'splits local and remotes, sorts remotes by join time, syncs toggles',
      build: buildBloc,
      act: (bloc) async {
        bloc.add(const CallStarted(params));
        await Future<void>.delayed(Duration.zero);
        statusController.add(ConnectionStatus.connected);
        participantsController.add([
          buildParticipant(isLocal: true, mic: false, cam: true),
          buildParticipant(
            isLocal: false,
            sid: 'sid-late',
            name: 'Carol',
            joinedAt: DateTime(2026, 1, 3),
          ),
          buildParticipant(
            isLocal: false,
            sid: 'sid-early',
            name: 'Bob',
            joinedAt: DateTime(2026, 1, 2),
          ),
        ]);
      },
      wait: const Duration(milliseconds: 50),
      expect: () => [
        const CallState(status: CallStatus.connecting),
        const CallState(status: CallStatus.connected),
        CallState(
          status: CallStatus.connected,
          localParticipant:
              buildParticipant(isLocal: true, mic: false, cam: true),
          remoteParticipants: [
            buildParticipant(
              isLocal: false,
              sid: 'sid-early',
              name: 'Bob',
              joinedAt: DateTime(2026, 1, 2),
            ),
            buildParticipant(
              isLocal: false,
              sid: 'sid-late',
              name: 'Carol',
              joinedAt: DateTime(2026, 1, 3),
            ),
          ],
          isMicEnabled: false,
        ),
      ],
      verify: (bloc) {
        expect(bloc.state.primaryRemote?.sid, 'sid-early');
      },
    );
  });

  group('controls', () {
    blocTest<CallBloc, CallState>(
      'mic toggle applies the value returned by the use case',
      build: buildBloc,
      setUp: () => when(() => toggleMicrophone.call(false))
          .thenAnswer((_) async => false),
      seed: () => const CallState(status: CallStatus.connected),
      act: (bloc) => bloc.add(const CallMicToggled()),
      expect: () => const [
        CallState(status: CallStatus.connected, isMicEnabled: false),
      ],
      verify: (_) => verify(() => toggleMicrophone.call(false)).called(1),
    );

    blocTest<CallBloc, CallState>(
      'camera toggle applies the value returned by the use case',
      build: buildBloc,
      setUp: () =>
          when(() => toggleCamera.call(false)).thenAnswer((_) async => false),
      seed: () => const CallState(status: CallStatus.connected),
      act: (bloc) => bloc.add(const CallCameraToggled()),
      expect: () => const [
        CallState(status: CallStatus.connected, isCameraEnabled: false),
      ],
    );

    blocTest<CallBloc, CallState>(
      'toggles are ignored before the call is connected',
      build: buildBloc,
      seed: () => const CallState(status: CallStatus.connecting),
      act: (bloc) => bloc
        ..add(const CallMicToggled())
        ..add(const CallCameraToggled()),
      expect: () => const <CallState>[],
      verify: (_) {
        verifyNever(() => toggleMicrophone.call(any()));
        verifyNever(() => toggleCamera.call(any()));
      },
    );
  });

  group('leave', () {
    blocTest<CallBloc, CallState>(
      'leave requests disconnect and emits ended',
      build: buildBloc,
      seed: () => const CallState(status: CallStatus.connected),
      act: (bloc) => bloc.add(const CallLeaveRequested()),
      expect: () => const [CallState(status: CallStatus.ended)],
      verify: (_) =>
          verify(() => leaveRoom.call()).called(greaterThanOrEqualTo(1)),
    );

    test('close tears the room down even without an explicit leave', () async {
      final bloc = buildBloc();
      await bloc.close();
      verify(() => leaveRoom.call()).called(1);
    });
  });
}
