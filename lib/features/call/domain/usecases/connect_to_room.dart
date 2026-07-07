import '../entities/connection_params.dart';
import '../repositories/call_repository.dart';

class ConnectToRoom {
  const ConnectToRoom(this._repository);

  final CallRepository _repository;

  Future<void> call(ConnectionParams params) => _repository.connect(params);
}
