import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/di/injection.dart';
import '../../../../core/theme/app_theme.dart';
import '../../domain/entities/connection_params.dart';
import '../../domain/entities/participant.dart';
import '../blocs/call/call_bloc.dart';
import '../widgets/call_control_bar.dart';
import '../widgets/participant_video_tile.dart';

class CallPage extends StatelessWidget {
  const CallPage({super.key, required this.params});

  static const route = '/call';

  final ConnectionParams params;

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => sl<CallBloc>()..add(CallStarted(params)),
      child: _CallView(roomId: params.roomId),
    );
  }
}

class _CallView extends StatefulWidget {
  const _CallView({required this.roomId});

  final String roomId;

  @override
  State<_CallView> createState() => _CallViewState();
}

class _CallViewState extends State<_CallView> {
  static const double _tileWidth = 112;
  static const double _tileHeight = 160;
  static const double _tileMargin = AppSpacing.md;

  /// Top-left of the draggable local preview; null until first laid out.
  Offset? _tilePosition;

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<CallBloc, CallState>(
      listenWhen: (previous, current) => previous.status != current.status,
      listener: (context, state) {
        switch (state.status) {
          case CallStatus.ended:
            _leaveToJoin(context);
          case CallStatus.error:
            ScaffoldMessenger.of(context)
              ..hideCurrentSnackBar()
              ..showSnackBar(
                SnackBar(content: Text(state.errorMessage ?? 'Call failed.')),
              );
            _leaveToJoin(context);
          case CallStatus.initial:
          case CallStatus.connecting:
          case CallStatus.connected:
          case CallStatus.reconnecting:
            break;
        }
      },
      builder: (context, state) {
        return PopScope(
          // System back must go through the same leave flow as the button —
          // a silent pop would leave the camera and mic hot.
          canPop: false,
          onPopInvokedWithResult: (didPop, _) {
            if (didPop) return;
            _confirmAndLeave(context);
          },
          child: Scaffold(
            backgroundColor: AppColors.background,
            body: _buildBody(context, state),
          ),
        );
      },
    );
  }

  Widget _buildBody(BuildContext context, CallState state) {
    switch (state.status) {
      case CallStatus.initial:
      case CallStatus.connecting:
        return _ConnectingView(roomId: widget.roomId);
      case CallStatus.error:
      case CallStatus.ended:
        // The listener is popping the route; render nothing meanwhile.
        return const SizedBox.shrink();
      case CallStatus.connected:
      case CallStatus.reconnecting:
        return _buildCall(context, state);
    }
  }

  Widget _buildCall(BuildContext context, CallState state) {
    final bloc = context.read<CallBloc>();
    final remote = state.primaryRemote;
    final local = state.localParticipant;

    return LayoutBuilder(
      builder: (context, constraints) {
        final defaultPosition = Offset(
          constraints.maxWidth - _tileWidth - _tileMargin,
          _tileMargin,
        );
        final position = _tilePosition ?? defaultPosition;

        return Stack(
          fit: StackFit.expand,
          children: [
            // Remote video (or waiting state) fills the screen.
            if (remote != null)
              ParticipantVideoTile(participant: remote)
            else
              _WaitingForOthers(roomId: widget.roomId),

            // Scrims keep the overlays legible over any video content.
            const _EdgeScrim(alignment: Alignment.topCenter),
            const _EdgeScrim(alignment: Alignment.bottomCenter),

            // Status pill (top).
            SafeArea(
              child: Align(
                alignment: Alignment.topCenter,
                child: Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.sm),
                  child: _StatusPill(
                    roomId: widget.roomId,
                    reconnecting: state.status == CallStatus.reconnecting,
                  ),
                ),
              ),
            ),

            // Draggable local preview.
            if (local != null)
              Positioned(
                left: position.dx,
                top: position.dy,
                width: _tileWidth,
                height: _tileHeight,
                child: GestureDetector(
                  onPanUpdate: (details) => _dragTile(details, constraints),
                  child: _LocalPreview(participant: local),
                ),
              ),

            // Controls (bottom).
            SafeArea(
              child: Align(
                alignment: Alignment.bottomCenter,
                child: CallControlBar(
                  isMicEnabled: state.isMicEnabled,
                  isCameraEnabled: state.isCameraEnabled,
                  onToggleMic: () => bloc.add(const CallMicToggled()),
                  onToggleCamera: () => bloc.add(const CallCameraToggled()),
                  onLeave: () => _confirmAndLeave(context),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  void _dragTile(DragUpdateDetails details, BoxConstraints constraints) {
    setState(() {
      final base = _tilePosition ??
          Offset(
            constraints.maxWidth - _tileWidth - _tileMargin,
            _tileMargin,
          );
      _tilePosition = Offset(
        (base.dx + details.delta.dx)
            .clamp(_tileMargin, constraints.maxWidth - _tileWidth - _tileMargin),
        (base.dy + details.delta.dy).clamp(
          _tileMargin,
          constraints.maxHeight - _tileHeight - _tileMargin,
        ),
      );
    });
  }

  /// Returns to the join screen, dismissing the call page AND anything stacked
  /// above it (e.g. an open "Leave call?" dialog). Popping to the first route
  /// is idempotent — if we're already there it removes nothing, so a second
  /// terminal event can never over-pop and empty the navigator.
  void _leaveToJoin(BuildContext context) {
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  Future<void> _confirmAndLeave(BuildContext context) async {
    final bloc = context.read<CallBloc>();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Leave call?'),
        content: const Text('You will be disconnected from this room.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Stay'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.danger,
              minimumSize: const Size(64, 44),
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Leave'),
          ),
        ],
      ),
    );
    if (confirmed ?? false) {
      bloc.add(const CallLeaveRequested());
    }
  }
}

/// Small rounded local-preview with a border, so it reads as a distinct layer
/// above the remote video.
class _LocalPreview extends StatelessWidget {
  const _LocalPreview({required this.participant});

  final Participant participant;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: Colors.white.withValues(alpha: 0.25)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.4),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: ParticipantVideoTile(participant: participant, compact: true),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.roomId, required this.reconnecting});

  final String roomId;
  final bool reconnecting;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (reconnecting)
            const SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Color(0xFFF59E0B),
              ),
            )
          else
            Container(
              width: 8,
              height: 8,
              decoration: const BoxDecoration(
                color: AppColors.success,
                shape: BoxShape.circle,
              ),
            ),
          const SizedBox(width: 8),
          Text(
            reconnecting ? 'Reconnecting' : roomId,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
          if (!reconnecting) ...[
            const _Dot(),
            const _CallDuration(),
          ],
        ],
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: 8),
      child: Text('·', style: TextStyle(color: AppColors.textSecondary)),
    );
  }
}

/// Live mm:ss call timer. Tabular figures stop the width from jittering.
class _CallDuration extends StatefulWidget {
  const _CallDuration();

  @override
  State<_CallDuration> createState() => _CallDurationState();
}

class _CallDurationState extends State<_CallDuration> {
  final Stopwatch _stopwatch = Stopwatch()..start();
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final elapsed = _stopwatch.elapsed;
    final minutes = elapsed.inMinutes.toString().padLeft(2, '0');
    final seconds = (elapsed.inSeconds % 60).toString().padLeft(2, '0');
    return Text(
      '$minutes:$seconds',
      style: const TextStyle(
        color: Colors.white,
        fontSize: 13,
        fontWeight: FontWeight.w500,
        fontFeatures: [FontFeature.tabularFigures()],
      ),
    );
  }
}

class _EdgeScrim extends StatelessWidget {
  const _EdgeScrim({required this.alignment});

  final Alignment alignment;

  @override
  Widget build(BuildContext context) {
    final top = alignment == Alignment.topCenter;
    return Align(
      alignment: alignment,
      child: IgnorePointer(
        child: Container(
          height: 140,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: top ? Alignment.topCenter : Alignment.bottomCenter,
              end: top ? Alignment.bottomCenter : Alignment.topCenter,
              colors: [
                Colors.black.withValues(alpha: 0.55),
                Colors.transparent,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ConnectingView extends StatelessWidget {
  const _ConnectingView({required this.roomId});

  final String roomId;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(color: AppColors.primary),
          const SizedBox(height: AppSpacing.lg),
          const Text(
            'Connecting…',
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Room · $roomId',
            style: const TextStyle(color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }
}

class _WaitingForOthers extends StatelessWidget {
  const _WaitingForOthers({required this.roomId});

  final String roomId;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AppColors.background,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(
                color: AppColors.surface,
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.border),
              ),
              child: const Icon(
                Icons.groups_outlined,
                size: 40,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            const Text(
              'Waiting for others to join',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 17,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
              child: Text(
                'Share Room ID "$roomId" so someone can join you.',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  height: 1.5,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
