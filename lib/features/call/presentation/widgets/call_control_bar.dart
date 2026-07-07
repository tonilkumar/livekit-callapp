import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';

class CallControlBar extends StatelessWidget {
  const CallControlBar({
    super.key,
    required this.isMicEnabled,
    required this.isCameraEnabled,
    required this.onToggleMic,
    required this.onToggleCamera,
    required this.onLeave,
  });

  final bool isMicEnabled;
  final bool isCameraEnabled;
  final VoidCallback onToggleMic;
  final VoidCallback onToggleCamera;
  final VoidCallback onLeave;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.lg),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _ControlButton(
            icon: isMicEnabled ? Icons.mic_rounded : Icons.mic_off_rounded,
            label: isMicEnabled ? 'Mic on' : 'Muted',
            active: isMicEnabled,
            onPressed: onToggleMic,
          ),
          const SizedBox(width: AppSpacing.lg),
          _ControlButton(
            icon: isCameraEnabled
                ? Icons.videocam_rounded
                : Icons.videocam_off_rounded,
            label: isCameraEnabled ? 'Camera' : 'Off',
            active: isCameraEnabled,
            onPressed: onToggleCamera,
          ),
          const SizedBox(width: AppSpacing.lg),
          _ControlButton(
            icon: Icons.call_end_rounded,
            label: 'Leave',
            danger: true,
            onPressed: onLeave,
          ),
        ],
      ),
    );
  }
}

class _ControlButton extends StatelessWidget {
  const _ControlButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.active = true,
    this.danger = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  /// For toggles: on = subtle surface, off = high-contrast white.
  final bool active;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final Color background;
    final Color foreground;
    if (danger) {
      background = AppColors.danger;
      foreground = AppColors.onPrimary;
    } else if (active) {
      background = Colors.white.withValues(alpha: 0.12);
      foreground = AppColors.textPrimary;
    } else {
      // "Off" state — invert so it clearly reads as disabled media.
      background = AppColors.textPrimary;
      foreground = AppColors.background;
    }

    return Semantics(
      button: true,
      label: label,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              color: background,
              shape: BoxShape.circle,
              border: danger || !active
                  ? null
                  : Border.all(color: AppColors.border),
            ),
            child: Material(
              color: Colors.transparent,
              shape: const CircleBorder(),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: onPressed,
                child: Icon(icon, color: foreground, size: 26),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
