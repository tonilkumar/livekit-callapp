import '../repositories/call_repository.dart';

class ToggleMicrophone {
  const ToggleMicrophone(this._repository);

  final CallRepository _repository;

  /// Returns the value actually applied by the SDK.
  Future<bool> call(bool enabled) => _repository.setMicrophoneEnabled(enabled);
}
