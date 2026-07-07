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
/// 1. Custom token endpoint — your own token server, full URL configurable:
///        --dart-define=LIVEKIT_TOKEN_ENDPOINT=https://your-server.example/token
///    Uses the SDK's [sdk.EndpointTokenSource]; the endpoint must return
///    `{ server_url, participant_token }`. This is the production path.
///
/// 2. Sandbox token server — the recommended dev path, no backend to run:
///        --dart-define=LIVEKIT_SANDBOX_ID=your-sandbox-id
///    Uses [sdk.SandboxTokenSource]. The hosted URL
///    (`https://{id}.sandbox.livekit.io`) is derived from the id, so it is
///    automatically per-project — nothing else to configure. Insecure by
///    design; development only.
///
/// 3. Static token — a single-device smoke test with a pre-minted token:
///        --dart-define=LIVEKIT_URL=wss://... --dart-define=LIVEKIT_TOKEN=eyJ...
///
/// The LiveKit API secret never ships inside the app.
class SandboxTokenService implements TokenService {
  SandboxTokenService();

  static const _endpointUrl = String.fromEnvironment('LIVEKIT_TOKEN_ENDPOINT');
  static const _sandboxId = String.fromEnvironment('LIVEKIT_SANDBOX_ID');
  static const _manualUrl = String.fromEnvironment('LIVEKIT_URL');
  static const _manualToken = String.fromEnvironment('LIVEKIT_TOKEN');

  final Random _random = Random();

  // Built lazily, only after config is confirmed (endpoint url or sandbox id).
  // A custom endpoint takes precedence; otherwise the sandbox source derives
  // its URL from the id, so it is per-project without any extra config.
  late final sdk.EndpointTokenSource _tokenSource = _endpointUrl.isNotEmpty
      ? sdk.EndpointTokenSource(url: Uri.parse(_endpointUrl))
      : sdk.SandboxTokenSource(sandboxId: _sandboxId);

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
    if (_endpointUrl.isEmpty && _sandboxId.isEmpty) {
      throw const TokenConfigFailure(
        'LiveKit is not configured. Pass --dart-define=LIVEKIT_SANDBOX_ID=<id> '
        '(hosted sandbox) or --dart-define=LIVEKIT_TOKEN_ENDPOINT=<url> '
        '(your own token server).',
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
