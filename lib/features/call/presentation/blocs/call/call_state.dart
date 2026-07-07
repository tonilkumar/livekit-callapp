part of 'call_bloc.dart';

enum CallStatus { initial, connecting, connected, reconnecting, error, ended }

final class CallState extends Equatable {
  const CallState({
    this.status = CallStatus.initial,
    this.localParticipant,
    this.remoteParticipants = const [],
    this.isMicEnabled = true,
    this.isCameraEnabled = true,
    this.errorMessage,
  });

  final CallStatus status;
  final Participant? localParticipant;

  /// Sorted by join time (earliest first).
  final List<Participant> remoteParticipants;

  final bool isMicEnabled;
  final bool isCameraEnabled;
  final String? errorMessage;

  /// v1 renders a single remote — the earliest to join.
  Participant? get primaryRemote =>
      remoteParticipants.isEmpty ? null : remoteParticipants.first;

  bool get isInCall =>
      status == CallStatus.connected || status == CallStatus.reconnecting;

  CallState copyWith({
    CallStatus? status,
    Participant? localParticipant,
    List<Participant>? remoteParticipants,
    bool? isMicEnabled,
    bool? isCameraEnabled,
    String? errorMessage,
  }) {
    return CallState(
      status: status ?? this.status,
      localParticipant: localParticipant ?? this.localParticipant,
      remoteParticipants: remoteParticipants ?? this.remoteParticipants,
      isMicEnabled: isMicEnabled ?? this.isMicEnabled,
      isCameraEnabled: isCameraEnabled ?? this.isCameraEnabled,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }

  @override
  List<Object?> get props => [
        status,
        localParticipant,
        remoteParticipants,
        isMicEnabled,
        isCameraEnabled,
        errorMessage,
      ];
}
