import '../entities/participant.dart';
import '../repositories/call_repository.dart';

class WatchParticipants {
  const WatchParticipants(this._repository);

  final CallRepository _repository;

  Stream<List<Participant>> call() => _repository.watchParticipants();
}
