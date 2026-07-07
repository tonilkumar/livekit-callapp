part of 'call_bloc.dart';

sealed class CallEvent extends Equatable {
  const CallEvent();

  @override
  List<Object?> get props => [];
}

final class CallStarted extends CallEvent {
  const CallStarted(this.params);

  final ConnectionParams params;

  @override
  List<Object?> get props => [params];
}

final class CallMicToggled extends CallEvent {
  const CallMicToggled();
}

final class CallCameraToggled extends CallEvent {
  const CallCameraToggled();
}

final class CallLeaveRequested extends CallEvent {
  const CallLeaveRequested();
}

/// Internal: bridges the repository's status stream into the bloc.
final class _ConnectionStatusChanged extends CallEvent {
  const _ConnectionStatusChanged(this.status);

  final ConnectionStatus status;

  @override
  List<Object?> get props => [status];
}

/// Internal: bridges the repository's participants stream into the bloc.
final class _ParticipantsUpdated extends CallEvent {
  const _ParticipantsUpdated(this.participants);

  final List<Participant> participants;

  @override
  List<Object?> get props => [participants];
}
