part of 'join_bloc.dart';

sealed class JoinEvent extends Equatable {
  const JoinEvent();

  @override
  List<Object?> get props => [];
}

final class JoinRoomIdChanged extends JoinEvent {
  const JoinRoomIdChanged(this.roomId);

  final String roomId;

  @override
  List<Object?> get props => [roomId];
}

final class JoinUserNameChanged extends JoinEvent {
  const JoinUserNameChanged(this.userName);

  final String userName;

  @override
  List<Object?> get props => [userName];
}

final class JoinSubmitted extends JoinEvent {
  const JoinSubmitted();
}

final class JoinReset extends JoinEvent {
  const JoinReset();
}
