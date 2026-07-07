import '../repositories/call_repository.dart';

class ToggleCamera {
  const ToggleCamera(this._repository);

  final CallRepository _repository;

  /// Returns the value actually applied by the SDK.
  Future<bool> call(bool enabled) => _repository.setCameraEnabled(enabled);
}
