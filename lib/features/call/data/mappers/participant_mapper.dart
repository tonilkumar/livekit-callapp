import 'package:livekit_client/livekit_client.dart' as lk;

import '../../domain/entities/participant.dart';
import '../../domain/entities/video_track_ref.dart';

/// Data-layer implementation of the opaque domain track handle.
class LiveKitVideoTrackRef extends VideoTrackRef {
  LiveKitVideoTrackRef(this.track);

  final lk.VideoTrack track;

  // The same underlying track object survives across snapshots, so identity
  // equality lets Equatable-based states skip redundant rebuilds.
  @override
  bool operator ==(Object other) =>
      other is LiveKitVideoTrackRef && identical(other.track, track);

  @override
  int get hashCode => identityHashCode(track);
}

class ParticipantMapper {
  const ParticipantMapper._();

  static Participant map(lk.Participant participant, {required bool isLocal}) {
    lk.VideoTrack? cameraTrack;
    for (final publication in participant.videoTrackPublications) {
      final track = publication.track;
      // Camera only — screen share is explicitly out of scope.
      if (publication.source == lk.TrackSource.camera &&
          !publication.muted &&
          track is lk.VideoTrack) {
        cameraTrack = track;
        break;
      }
    }

    var micEnabled = false;
    for (final publication in participant.audioTrackPublications) {
      if (publication.source == lk.TrackSource.microphone &&
          !publication.muted &&
          publication.track != null) {
        micEnabled = true;
        break;
      }
    }

    final identity = participant.identity;
    return Participant(
      sid: participant.sid,
      identity: identity,
      displayName: _stripIdentitySuffix(identity),
      isLocal: isLocal,
      isMicEnabled: micEnabled,
      isCameraEnabled: cameraTrack != null,
      isSpeaking: participant.isSpeaking,
      joinedAt: participant.joinedAt,
      videoTrack: cameraTrack == null ? null : LiveKitVideoTrackRef(cameraTrack),
    );
  }

  static final _suffixPattern = RegExp(r'-[a-z0-9]{4}$');

  /// Identities are minted as `name-<4 random chars>` (see SandboxTokenService);
  /// strip the suffix for display.
  static String _stripIdentitySuffix(String identity) =>
      identity.replaceFirst(_suffixPattern, '');
}
