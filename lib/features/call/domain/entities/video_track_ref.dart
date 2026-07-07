/// Opaque handle to a renderable video track.
///
/// The domain layer stays free of SDK types: the data layer wraps LiveKit's
/// track in an implementation of this marker, and the single SDK-aware widget
/// (LiveKitVideoView) downcasts it back for rendering. No other presentation
/// or domain code may look inside.
abstract class VideoTrackRef {}
