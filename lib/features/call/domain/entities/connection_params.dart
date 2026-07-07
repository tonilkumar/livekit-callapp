import 'package:equatable/equatable.dart';

/// What the join screen collects. Token/server resolution happens in the data
/// layer; the domain never sees credentials.
class ConnectionParams extends Equatable {
  const ConnectionParams({required this.roomId, required this.userName});

  /// Normalized (trimmed + lowercased) room identifier.
  final String roomId;

  /// Display name entered on the join screen.
  final String userName;

  @override
  List<Object?> get props => [roomId, userName];
}
