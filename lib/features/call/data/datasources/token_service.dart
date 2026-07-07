import 'dart:async';
import 'dart:math';

import 'package:livekit_client/livekit_client.dart' as sdk;

import '../../../../core/error/failures.dart';

class ConnectionDetails {
  const ConnectionDetails({required this.serverUrl, required this.token});

  final String serverUrl;
  final String token;
}

abstract class TokenService {
  Future<ConnectionDetails> fetchConnectionDetails({
    required String roomId,
    required String userName,
  });
}

/// Resolves LiveKit connection details (server URL + JWT) for dev/testing.
///
/// Configured at build time via --dart-define, in priority order:
///
/// 1. Sandbox token server — the recommended dev path, no backend to run:
///        flutter run --dart-define=LIVEKIT_SANDBOX_ID=your-sandbox-id
///    Delegates to the SDK's [sdk.SandboxTokenSource], which calls LiveKit's
///    hosted sandbox at `https://{id}.sandbox.livekit.io` and returns a fresh
///    token. Insecure by design — development only.
///
/// 2. Static token — a single-device smoke test with a pre-minted token:
///        flutter run --dart-define=LIVEKIT_URL=wss://... --dart-define=LIVEKIT_TOKEN=eyJ...
///
/// Production must mint tokens on your own backend (see LiveKit's
/// EndpointTokenSource); the LiveKit API secret never ships inside the app.
class SandboxTokenService implements TokenService {
  SandboxTokenService();

  static const _sandboxId = String.fromEnvironment('LIVEKIT_SANDBOX_ID');
  static const _manualUrl = String.fromEnvironment('LIVEKIT_URL');
  static const _manualToken = String.fromEnvironment('LIVEKIT_TOKEN');

  final Random _random = Random();

  // Built lazily, only after the sandbox id is confirmed non-empty.
  late final sdk.SandboxTokenSource _tokenSource =
      sdk.SandboxTokenSource(sandboxId: _sandboxId);

  @override
  Future<ConnectionDetails> fetchConnectionDetails({
    required String roomId,
    required String userName,
  }) async {
    if (_manualUrl.isNotEmpty && _manualToken.isNotEmpty) {
      return const ConnectionDetails(
        serverUrl: _manualUrl,
        token: _manualToken,
      );
    }
    if (_sandboxId.isEmpty) {
      throw const TokenConfigFailure(
        'LiveKit is not configured. Run the app with '
        '--dart-define=LIVEKIT_SANDBOX_ID=<your sandbox id>.',
      );
    }

    // Same identity => LiveKit disconnects the earlier session, so give each
    // join a unique identity while keeping the display name clean.
    final identity = '$userName-${_suffix()}';

    final sdk.TokenSourceResponse response;
    try {
      response = await _tokenSource
          .fetch(sdk.TokenRequestOptions(
            roomName: roomId,
            participantName: userName,
            participantIdentity: identity,
          ))
          .timeout(const Duration(seconds: 15));
    } on TimeoutException {
      throw const ConnectionFailure(
        'Timed out reaching the token server. Check your network and retry.',
      );
    } catch (_) {
      throw const ConnectionFailure(
        'Could not get a token from the sandbox. Check the sandbox ID and '
        'your network, then retry.',
      );
    }

    if (response.serverUrl.isEmpty || response.participantToken.isEmpty) {
      throw const ConnectionFailure(
        'Token server returned an incomplete response.',
      );
    }
    return ConnectionDetails(
      serverUrl: response.serverUrl,
      token: response.participantToken,
    );
  }

  String _suffix() {
    const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
    return List.generate(4, (_) => chars[_random.nextInt(chars.length)]).join();
  }
}
