/// Domain-level failures.
///
/// Everything thrown across the repository boundary is one of these, so the
/// UI only ever has a small, fixed set of user-facing messages to show.
sealed class Failure implements Exception {
  const Failure(this.message);

  final String message;

  @override
  String toString() => message;
}

class PermissionFailure extends Failure {
  const PermissionFailure([
    super.message =
        'Camera and microphone permissions are required to join a call.',
  ]);
}

/// LiveKit credentials are injected at build time; this fires when they are
/// missing (e.g. the sandbox ID has not been provided yet).
class TokenConfigFailure extends Failure {
  const TokenConfigFailure([
    super.message = 'LiveKit is not configured yet.',
  ]);
}

class ConnectionFailure extends Failure {
  const ConnectionFailure([
    super.message =
        'Could not connect to the call. Check your network and try again.',
  ]);
}

class UnknownFailure extends Failure {
  const UnknownFailure([
    super.message = 'Something went wrong. Please try again.',
  ]);
}
