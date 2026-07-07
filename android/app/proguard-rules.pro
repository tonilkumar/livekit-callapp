# flutter_webrtc / LiveKit: native WebRTC classes are reached via JNI and must
# not be stripped or renamed by R8.
-keep class org.webrtc.** { *; }
