import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;

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

/// Dev-only token source backed by the LiveKit Cloud sandbox token server.
///
/// Configuration comes from --dart-define:
///
///     flutter run --dart-define=LIVEKIT_SANDBOX_ID=token-server-xxxxxx
///
/// For a single-device smoke test a manual pair can be supplied instead:
///
///     flutter run --dart-define=LIVEKIT_URL=wss://... --dart-define=LIVEKIT_TOKEN=eyJ...
///
/// Production must swap this for a backend endpoint that mints tokens — the
/// LiveKit API secret never ships inside the app.
class SandboxTokenService implements TokenService {
  SandboxTokenService(this._client);

  static const _sandboxId = String.fromEnvironment('LIVEKIT_SANDBOX_ID');
  static const _manualUrl = String.fromEnvironment('LIVEKIT_URL');
  static const _manualToken = String.fromEnvironment('LIVEKIT_TOKEN');
  static const _endpoint =
      'https://cloud-api.livekit.io/api/sandbox/connection-details';

  final http.Client _client;
  final Random _random = Random();

  @override
  Future<ConnectionDetails> fetchConnectionDetails({
    required String roomId,
    required String userName,
  }) async {
    if (_manualUrl.isNotEmpty && _manualToken.isNotEmpty) {
      return const ConnectionDetails(serverUrl: _manualUrl, token: _manualToken);
    }
    if (_sandboxId.isEmpty) {
      throw const TokenConfigFailure(
        'LiveKit is not configured. Run the app with '
        '--dart-define=LIVEKIT_SANDBOX_ID=<your sandbox id>.',
      );
    }

    // Two participants with the same identity kick each other off the room,
    // so the identity gets a random suffix; the UI strips it for display.
    final identity = '$userName-${_suffix()}';
    final uri = Uri.parse(_endpoint).replace(queryParameters: {
      'roomName': roomId,
      'participantName': identity,
    });

    final http.Response response;
    try {
      response = await _client
          .post(uri, headers: {'X-Sandbox-ID': _sandboxId})
          .timeout(const Duration(seconds: 10));
    } on Exception {
      throw const ConnectionFailure(
        'Could not reach the token server. Check your network and try again.',
      );
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ConnectionFailure(
        'Token server rejected the request (HTTP ${response.statusCode}).',
      );
    }

    final Object? decoded;
    try {
      decoded = jsonDecode(response.body);
    } catch (_) {
      throw const ConnectionFailure(
        'Token server returned an unexpected response.',
      );
    }
    if (decoded is! Map<String, dynamic>) {
      throw const ConnectionFailure(
        'Token server returned an unexpected response.',
      );
    }
    final serverUrl = decoded['serverUrl'] as String?;
    final token = decoded['participantToken'] as String?;
    if (serverUrl == null || serverUrl.isEmpty || token == null || token.isEmpty) {
      throw const ConnectionFailure(
        'Token server returned an unexpected response.',
      );
    }
    return ConnectionDetails(serverUrl: serverUrl, token: token);
  }

  String _suffix() {
    const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
    return List.generate(4, (_) => chars[_random.nextInt(chars.length)]).join();
  }
}
