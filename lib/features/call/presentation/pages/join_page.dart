import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/di/injection.dart';
import '../../../../core/permissions/permission_service.dart';
import '../../../../core/theme/app_theme.dart';
import '../blocs/join/join_bloc.dart';
import 'call_page.dart';

class JoinPage extends StatelessWidget {
  const JoinPage({super.key});

  static const route = '/';

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => sl<JoinBloc>(),
      child: const _JoinView(),
    );
  }
}

class _JoinView extends StatelessWidget {
  const _JoinView();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [AppColors.background, AppColors.backgroundDeep],
          ),
        ),
        child: SafeArea(
          child: BlocConsumer<JoinBloc, JoinState>(
            listenWhen: (previous, current) => previous.status != current.status,
            listener: _onStateChanged,
            builder: (context, state) {
              final bloc = context.read<JoinBloc>();
              return Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 420),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const _BrandHeader(),
                        const SizedBox(height: AppSpacing.xl),
                        TextField(
                          onChanged: (value) =>
                              bloc.add(JoinRoomIdChanged(value)),
                          enabled: !state.isSubmitting,
                          maxLength: 64,
                          textInputAction: TextInputAction.next,
                          autocorrect: false,
                          textCapitalization: TextCapitalization.none,
                          style: const TextStyle(color: AppColors.textPrimary),
                          decoration: const InputDecoration(
                            labelText: 'Room ID',
                            hintText: 'e.g. team-standup',
                            counterText: '',
                            helperText: 'Share this ID with whoever you want '
                                'to call.',
                            prefixIcon: Icon(Icons.meeting_room_outlined),
                          ),
                        ),
                        const SizedBox(height: AppSpacing.md),
                        TextField(
                          onChanged: (value) =>
                              bloc.add(JoinUserNameChanged(value)),
                          enabled: !state.isSubmitting,
                          maxLength: 64,
                          textInputAction: TextInputAction.done,
                          onSubmitted: (_) {
                            if (state.isValid) bloc.add(const JoinSubmitted());
                          },
                          style: const TextStyle(color: AppColors.textPrimary),
                          decoration: const InputDecoration(
                            labelText: 'Your Name',
                            hintText: 'e.g. Alex',
                            counterText: '',
                            prefixIcon: Icon(Icons.person_outline),
                          ),
                        ),
                        _InlineError(state: state),
                        const SizedBox(height: AppSpacing.lg),
                        FilledButton(
                          onPressed: state.isValid && !state.isSubmitting
                              ? () => bloc.add(const JoinSubmitted())
                              : null,
                          child: state.isSubmitting
                              ? const _ButtonBusy()
                              : const Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.videocam_rounded, size: 20),
                                    SizedBox(width: AppSpacing.sm),
                                    Text('Join Call'),
                                  ],
                                ),
                        ),
                        const SizedBox(height: AppSpacing.lg),
                        const _SecuredFooter(),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  void _onStateChanged(BuildContext context, JoinState state) {
    switch (state.status) {
      case JoinStatus.ready:
        final params = state.params;
        if (params == null) return;
        Navigator.of(context).pushNamed(CallPage.route, arguments: params);
        // Reset so returning here doesn't re-trigger navigation.
        context.read<JoinBloc>().add(const JoinReset());
      case JoinStatus.permissionPermanentlyDenied:
        _showOpenSettingsDialog(context, state.errorMessage);
      // failure / permissionDenied are surfaced inline (see _InlineError).
      case JoinStatus.permissionDenied:
      case JoinStatus.failure:
      case JoinStatus.initial:
      case JoinStatus.requestingPermissions:
        break;
    }
  }

  void _showOpenSettingsDialog(BuildContext context, String? message) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Permissions needed'),
        content: Text(
          message ??
              'Camera and microphone access are blocked. Enable them in '
                  'Settings to join a call.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              minimumSize: const Size(64, 44),
            ),
            onPressed: () {
              Navigator.of(dialogContext).pop();
              sl<PermissionService>().openSettings();
            },
            child: const Text('Open Settings'),
          ),
        ],
      ),
    );
  }
}

class _BrandHeader extends StatelessWidget {
  const _BrandHeader();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 76,
          height: 76,
          decoration: BoxDecoration(
            color: AppColors.primary,
            borderRadius: BorderRadius.circular(AppRadius.lg),
            boxShadow: [
              BoxShadow(
                color: AppColors.primary.withValues(alpha: 0.35),
                blurRadius: 28,
                spreadRadius: 2,
              ),
            ],
          ),
          child: const Icon(
            Icons.videocam_rounded,
            size: 40,
            color: AppColors.onPrimary,
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        Text(
          'Video Call',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.headlineMedium,
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          'Enter a room to start talking',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      ],
    );
  }
}

class _InlineError extends StatelessWidget {
  const _InlineError({required this.state});

  final JoinState state;

  @override
  Widget build(BuildContext context) {
    final showError = (state.status == JoinStatus.failure ||
            state.status == JoinStatus.permissionDenied) &&
        state.errorMessage != null;
    if (!showError) return const SizedBox(height: AppSpacing.xs);

    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.error_outline, size: 18, color: AppColors.danger),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              state.errorMessage!,
              style: const TextStyle(color: AppColors.danger, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}

class _ButtonBusy extends StatelessWidget {
  const _ButtonBusy();

  @override
  Widget build(BuildContext context) {
    return const Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: AppColors.textSecondary,
          ),
        ),
        SizedBox(width: AppSpacing.sm),
        Text('Preparing…'),
      ],
    );
  }
}

class _SecuredFooter extends StatelessWidget {
  const _SecuredFooter();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(Icons.lock_outline, size: 14, color: AppColors.textFaint),
        const SizedBox(width: 6),
        Text(
          'End-to-end media over LiveKit',
          style: TextStyle(
            color: AppColors.textFaint,
            fontSize: 12,
            letterSpacing: 0.2,
          ),
        ),
      ],
    );
  }
}
