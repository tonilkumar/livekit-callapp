part of 'join_bloc.dart';

enum JoinStatus {
  initial,
  requestingPermissions,
  ready,
  permissionDenied,
  permissionPermanentlyDenied,
  failure,
}

final class JoinState extends Equatable {
  const JoinState({
    this.roomId = '',
    this.userName = '',
    this.status = JoinStatus.initial,
    this.errorMessage,
    this.params,
  });

  final String roomId;
  final String userName;
  final JoinStatus status;
  final String? errorMessage;

  /// Set when [status] is [JoinStatus.ready]; consumed by navigation.
  final ConnectionParams? params;

  bool get isValid =>
      roomId.trim().isNotEmpty && userName.trim().isNotEmpty;

  bool get isSubmitting => status == JoinStatus.requestingPermissions;

  JoinState copyWith({
    String? roomId,
    String? userName,
    JoinStatus? status,
    String? errorMessage,
    ConnectionParams? params,
  }) {
    return JoinState(
      roomId: roomId ?? this.roomId,
      userName: userName ?? this.userName,
      status: status ?? this.status,
      // Deliberately not `?? this.errorMessage`: every emit either sets a
      // fresh message or clears the previous one.
      errorMessage: errorMessage,
      params: params ?? this.params,
    );
  }

  @override
  List<Object?> get props => [roomId, userName, status, errorMessage, params];
}
