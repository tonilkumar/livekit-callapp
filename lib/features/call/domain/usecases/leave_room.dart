import '../repositories/call_repository.dart';

class LeaveRoom {
  const LeaveRoom(this._repository);

  final CallRepository _repository;

  Future<void> call() => _repository.disconnect();
}
