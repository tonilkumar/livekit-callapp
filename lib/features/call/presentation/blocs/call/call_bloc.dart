import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';

import '../../../../../core/error/failures.dart';
import '../../../domain/entities/connection_params.dart';
import '../../../domain/entities/connection_status.dart';
import '../../../domain/entities/participant.dart';
import '../../../domain/usecases/connect_to_room.dart';
import '../../../domain/usecases/leave_room.dart';
import '../../../domain/usecases/toggle_camera.dart';
import '../../../domain/usecases/toggle_microphone.dart';
import '../../../domain/usecases/watch_connection_status.dart';
import '../../../domain/usecases/watch_participants.dart';

part 'call_event.dart';
part 'call_state.dart';

/// ViewModel for the call screen: owns the connection lifecycle from
/// [CallStarted] through [CallLeaveRequested] / [close].
class CallBloc extends Bloc<CallEvent, CallState> {
  CallBloc({
    required ConnectToRoom connectToRoom,
    required LeaveRoom leaveRoom,
    required ToggleMicrophone toggleMicrophone,
    required ToggleCamera toggleCamera,
    required WatchConnectionStatus watchConnectionStatus,
    required WatchParticipants watchParticipants,
  })  : _connectToRoom = connectToRoom,
        _leaveRoom = leaveRoom,
        _toggleMicrophone = toggleMicrophone,
        _toggleCamera = toggleCamera,
        _watchConnectionStatus = watchConnectionStatus,
        _watchParticipants = watchParticipants,
        super(const CallState()) {
    on<CallStarted>(_onStarted);
    on<CallMicToggled>(_onMicToggled);
    on<CallCameraToggled>(_onCameraToggled);
    on<CallLeaveRequested>(_onLeaveRequested);
    on<_ConnectionStatusChanged>(_onConnectionStatusChanged);
    on<_ParticipantsUpdated>(_onParticipantsUpdated);
  }

  final ConnectToRoom _connectToRoom;
  final LeaveRoom _leaveRoom;
  final ToggleMicrophone _toggleMicrophone;
  final ToggleCamera _toggleCamera;
  final WatchConnectionStatus _watchConnectionStatus;
  final WatchParticipants _watchParticipants;

  StreamSubscription<ConnectionStatus>? _statusSubscription;
  StreamSubscription<List<Participant>>? _participantsSubscription;
  bool _leaving = false;

  Future<void> _onStarted(CallStarted event, Emitter<CallState> emit) async {
    if (state.status != CallStatus.initial) return;
    emit(state.copyWith(status: CallStatus.connecting));

    // Repository streams are bridged in as internal events so all state
    // changes flow through a single place.
    _statusSubscription = _watchConnectionStatus().listen((status) {
      if (!isClosed) add(_ConnectionStatusChanged(status));
    });
    _participantsSubscription = _watchParticipants().listen((participants) {
      if (!isClosed) add(_ParticipantsUpdated(participants));
    });

    try {
      await _connectToRoom(event.params);
    } on Failure catch (failure) {
      _emitConnectError(emit, failure.message);
    } catch (_) {
      _emitConnectError(emit, 'Could not join the call. Please try again.');
    }
  }

  void _emitConnectError(Emitter<CallState> emit, String message) {
    // If the user already left while connecting, the call is terminal — don't
    // resurrect it into an error state (which would re-trigger navigation).
    if (state.status == CallStatus.ended || state.status == CallStatus.error) {
      return;
    }
    emit(state.copyWith(status: CallStatus.error, errorMessage: message));
  }

  void _onConnectionStatusChanged(
    _ConnectionStatusChanged event,
    Emitter<CallState> emit,
  ) {
    // Terminal states win: a trailing "disconnected" from teardown must not
    // overwrite an error the user still has to see.
    if (state.status == CallStatus.error || state.status == CallStatus.ended) {
      return;
    }
    switch (event.status) {
      case ConnectionStatus.connecting:
        emit(state.copyWith(status: CallStatus.connecting));
      case ConnectionStatus.connected:
        emit(state.copyWith(status: CallStatus.connected));
      case ConnectionStatus.reconnecting:
        emit(state.copyWith(status: CallStatus.reconnecting));
      case ConnectionStatus.disconnected:
        emit(state.copyWith(status: CallStatus.ended));
      case ConnectionStatus.failed:
        emit(state.copyWith(
          status: CallStatus.error,
          errorMessage: 'Connection lost.',
        ));
    }
  }

  void _onParticipantsUpdated(
    _ParticipantsUpdated event,
    Emitter<CallState> emit,
  ) {
    Participant? local;
    final remotes = <Participant>[];
    for (final participant in event.participants) {
      if (participant.isLocal) {
        local = participant;
      } else {
        remotes.add(participant);
      }
    }
    remotes.sort((a, b) => a.joinedAt.compareTo(b.joinedAt));
    emit(state.copyWith(
      localParticipant: local,
      remoteParticipants: remotes,
      // The published tracks are the single source of truth for the
      // control-bar toggles.
      isMicEnabled: local?.isMicEnabled ?? state.isMicEnabled,
      isCameraEnabled: local?.isCameraEnabled ?? state.isCameraEnabled,
    ));
  }

  Future<void> _onMicToggled(
    CallMicToggled event,
    Emitter<CallState> emit,
  ) async {
    if (!_controlsAvailable) return;
    try {
      final applied = await _toggleMicrophone(!state.isMicEnabled);
      emit(state.copyWith(isMicEnabled: applied));
      // A confirming snapshot from the participants stream keeps state honest.
    } catch (_) {
      // Toggling can throw transiently (e.g. mid-reconnect); ignore and let
      // the next participants snapshot reconcile the button.
    }
  }

  Future<void> _onCameraToggled(
    CallCameraToggled event,
    Emitter<CallState> emit,
  ) async {
    if (!_controlsAvailable) return;
    try {
      final applied = await _toggleCamera(!state.isCameraEnabled);
      emit(state.copyWith(isCameraEnabled: applied));
    } catch (_) {
      // See _onMicToggled.
    }
  }

  Future<void> _onLeaveRequested(
    CallLeaveRequested event,
    Emitter<CallState> emit,
  ) async {
    if (_leaving) return;
    _leaving = true;
    try {
      await _leaveRoom();
    } catch (_) {
      // Leaving must always succeed from the user's perspective.
    }
    emit(state.copyWith(status: CallStatus.ended));
  }

  bool get _controlsAvailable =>
      state.status == CallStatus.connected ||
      state.status == CallStatus.reconnecting;

  @override
  Future<void> close() async {
    await _statusSubscription?.cancel();
    await _participantsSubscription?.cancel();
    // Safety net: leaving the screen always tears the room down, even when
    // the route pops without an explicit leave. disconnect() is idempotent.
    try {
      await _leaveRoom();
    } catch (_) {}
    return super.close();
  }
}
