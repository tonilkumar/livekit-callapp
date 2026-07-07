import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';

import '../../../../../core/permissions/permission_service.dart';
import '../../../domain/entities/connection_params.dart';

part 'join_event.dart';
part 'join_state.dart';

/// ViewModel for the join screen: form state, validation, and the
/// permission gate. It never connects — the call screen owns the
/// connection lifecycle.
class JoinBloc extends Bloc<JoinEvent, JoinState> {
  JoinBloc(this._permissionService) : super(const JoinState()) {
    on<JoinRoomIdChanged>(_onRoomIdChanged);
    on<JoinUserNameChanged>(_onUserNameChanged);
    on<JoinSubmitted>(_onSubmitted);
    on<JoinReset>(_onReset);
  }

  static final _roomIdPattern = RegExp(r'^[a-z0-9\-_]+$');

  final PermissionService _permissionService;

  void _onRoomIdChanged(JoinRoomIdChanged event, Emitter<JoinState> emit) {
    emit(state.copyWith(roomId: event.roomId, status: JoinStatus.initial));
  }

  void _onUserNameChanged(JoinUserNameChanged event, Emitter<JoinState> emit) {
    emit(state.copyWith(userName: event.userName, status: JoinStatus.initial));
  }

  Future<void> _onSubmitted(
    JoinSubmitted event,
    Emitter<JoinState> emit,
  ) async {
    if (state.isSubmitting) return;

    // Clear any prior failure/denied status first, so re-submitting the SAME
    // invalid input still produces a distinct state change — otherwise the
    // equal failure state is deduped and the error feedback never re-shows.
    if (state.status != JoinStatus.initial) {
      emit(state.copyWith(status: JoinStatus.initial));
    }

    // Room ids are case-insensitive by convention here — "Room1" and "room1"
    // silently landing in different rooms is a classic support trap.
    final roomId = state.roomId.trim().toLowerCase();
    final userName = state.userName.trim();

    if (roomId.isEmpty || userName.isEmpty) {
      emit(state.copyWith(
        status: JoinStatus.failure,
        errorMessage: 'Enter a room ID and your name.',
      ));
      return;
    }
    if (!_roomIdPattern.hasMatch(roomId)) {
      emit(state.copyWith(
        status: JoinStatus.failure,
        errorMessage:
            'Room ID can only contain letters, numbers, "-" and "_".',
      ));
      return;
    }

    emit(state.copyWith(status: JoinStatus.requestingPermissions));
    final result = await _permissionService.requestCallPermissions();
    switch (result) {
      case CallPermissionResult.granted:
        emit(state.copyWith(
          status: JoinStatus.ready,
          params: ConnectionParams(roomId: roomId, userName: userName),
        ));
      case CallPermissionResult.denied:
        emit(state.copyWith(
          status: JoinStatus.permissionDenied,
          errorMessage:
              'Camera and microphone access are required to join a call.',
        ));
      case CallPermissionResult.permanentlyDenied:
        emit(state.copyWith(
          status: JoinStatus.permissionPermanentlyDenied,
          errorMessage:
              'Camera and microphone access are blocked. Enable them in '
              'Settings to join a call.',
        ));
    }
  }

  /// Dispatched after navigating to the call screen so returning to the join
  /// screen doesn't re-trigger navigation from a stale `ready` state.
  void _onReset(JoinReset event, Emitter<JoinState> emit) {
    emit(JoinState(roomId: state.roomId, userName: state.userName));
  }
}
