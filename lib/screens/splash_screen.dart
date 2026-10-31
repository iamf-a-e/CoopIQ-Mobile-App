import 'dart:async';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

/// Plays assets/videos/splash.mp4 muted, then replaces itself with [next]
/// (the AuthGate: login screen for signed-out users, the app for signed-in ones).
class SplashVideoScreen extends StatefulWidget {
  final Widget next;
  const SplashVideoScreen({super.key, required this.next});

  @override
  State<SplashVideoScreen> createState() => _SplashVideoScreenState();
}

class _SplashVideoScreenState extends State<SplashVideoScreen> {
  late final VideoPlayerController _controller;
  Timer? _fallback;
  bool _navigated = false;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.asset(
      'assets/videos/splash.mp4',
      // Muted video should not pause music or calls playing in other apps.
      videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
    );
    _controller.addListener(_onTick);
    _controller.initialize().timeout(const Duration(seconds: 6)).then((_) async {
      if (!mounted) return;
      await _controller.setVolume(0); // mute before playing so there is no audio blip
      await _controller.play();
      if (!mounted) return;
      setState(() {});
      // Safety net in case the "completed" event never fires.
      _fallback = Timer(_controller.value.duration + const Duration(seconds: 2), _goNext);
    }).catchError((_) => _goNext());
  }

  void _onTick() {
    final v = _controller.value;
    if (v.hasError || (v.isInitialized && v.isCompleted)) _goNext();
  }

  void _goNext() {
    if (_navigated || !mounted) return;
    _navigated = true;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => widget.next),
    );
  }

  @override
  void dispose() {
    _fallback?.cancel();
    _controller.removeListener(_onTick);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: _controller.value.isInitialized
            ? AspectRatio(
                aspectRatio: _controller.value.aspectRatio,
                child: VideoPlayer(_controller),
              )
            : const SizedBox.shrink(),
      ),
    );
  }
}
