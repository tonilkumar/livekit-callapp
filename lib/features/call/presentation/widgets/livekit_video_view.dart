import 'package:flutter/material.dart';
import 'package:livekit_client/livekit_client.dart' as lk;

import '../../data/mappers/participant_mapper.dart';
import '../../domain/entities/video_track_ref.dart';

/// The ONE widget allowed to see LiveKit types on the presentation side.
///
/// LiveKit's renderer needs the SDK's VideoTrack object, so this widget
/// downcasts the opaque domain [VideoTrackRef] back to the data-layer
/// wrapper. Keep every other widget and bloc SDK-free.
class LiveKitVideoView extends StatelessWidget {
  const LiveKitVideoView({super.key, required this.trackRef});

  final VideoTrackRef trackRef;

  @override
  Widget build(BuildContext context) {
    final ref = trackRef;
    if (ref is! LiveKitVideoTrackRef) {
      return const ColoredBox(color: Colors.black);
    }
    // The renderer mirrors the local front camera automatically
    // (mirrorMode defaults to auto) — no manual Transform needed.
    return lk.VideoTrackRenderer(
      ref.track,
      fit: lk.VideoViewFit.cover,
    );
  }
}
