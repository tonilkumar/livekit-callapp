import 'package:equatable/equatable.dart';

import 'video_track_ref.dart';

class Participant extends Equatable {
  const Participant({
    required this.sid,
    required this.identity,
    required this.displayName,
    required this.isLocal,
    required this.isMicEnabled,
    required this.isCameraEnabled,
    required this.isSpeaking,
    required this.joinedAt,
    this.videoTrack,
  });

  /// Server-side participant sid.
  final String sid;

  /// Unique identity on the server (display name plus a random suffix, so two
  /// users with the same name don't kick each other off).
  final String identity;

  /// Name shown in the UI ([identity] with the suffix stripped).
  final String displayName;

  final bool isLocal;
  final bool isMicEnabled;
  final bool isCameraEnabled;
  final bool isSpeaking;

  /// Used to pick the primary remote deterministically (earliest joined).
  final DateTime joinedAt;

  /// Camera track when published and subscribed; null renders a placeholder.
  final VideoTrackRef? videoTrack;

  @override
  List<Object?> get props => [
        sid,
        identity,
        displayName,
        isLocal,
        isMicEnabled,
        isCameraEnabled,
        isSpeaking,
        joinedAt,
        videoTrack,
      ];
}
