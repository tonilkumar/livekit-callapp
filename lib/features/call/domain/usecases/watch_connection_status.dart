import '../entities/connection_status.dart';
import '../repositories/call_repository.dart';

class WatchConnectionStatus {
  const WatchConnectionStatus(this._repository);

  final CallRepository _repository;

  Stream<ConnectionStatus> call() => _repository.watchConnectionStatus();
}
