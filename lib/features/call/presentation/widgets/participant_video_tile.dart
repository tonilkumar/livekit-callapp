import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../domain/entities/participant.dart';
import 'livekit_video_view.dart';

/// Renders one participant: their camera feed when available, otherwise an
/// initials avatar. Overlays the name, a muted-mic badge, and a speaking
/// highlight.
class ParticipantVideoTile extends StatelessWidget {
  const ParticipantVideoTile({
    super.key,
    required this.participant,
    this.compact = false,
  });

  final Participant participant;

  /// Compact styling for the small local-preview tile.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final track = participant.videoTrack;
    final showVideo = track != null && participant.isCameraEnabled;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        border: participant.isSpeaking
            ? Border.all(color: AppColors.success, width: 2.5)
            : null,
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (showVideo)
            LiveKitVideoView(trackRef: track)
          else
            _AvatarPlaceholder(name: participant.displayName, compact: compact),
          Positioned(
            left: compact ? 6 : AppSpacing.md,
            bottom: compact ? 6 : AppSpacing.md,
            child: _NamePill(
              name: participant.isLocal
                  ? '${participant.displayName} (you)'
                  : participant.displayName,
              muted: !participant.isMicEnabled,
              compact: compact,
            ),
          ),
        ],
      ),
    );
  }
}

class _NamePill extends StatelessWidget {
  const _NamePill({
    required this.name,
    required this.muted,
    required this.compact,
  });

  final String name;
  final bool muted;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 8 : 10,
        vertical: compact ? 3 : 5,
      ),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (muted) ...[
            Icon(
              Icons.mic_off_rounded,
              size: compact ? 12 : 15,
              color: AppColors.danger,
            ),
            const SizedBox(width: 5),
          ],
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: compact ? 90 : 220),
            child: Text(
              name,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Colors.white,
                fontSize: compact ? 11 : 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AvatarPlaceholder extends StatelessWidget {
  const _AvatarPlaceholder({required this.name, required this.compact});

  final String name;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final trimmed = name.trim();
    final initial = trimmed.isEmpty ? '?' : trimmed[0].toUpperCase();
    final radius = compact ? 20.0 : 40.0;
    return Center(
      child: Container(
        width: radius * 2,
        height: radius * 2,
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [AppColors.primary, AppColors.primaryPressed],
          ),
        ),
        alignment: Alignment.center,
        child: Text(
          initial,
          style: TextStyle(
            fontSize: radius,
            color: Colors.white,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}
