import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key, required this.child});

  final Widget child;

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  static const _videoUrl =
      'https://raw.githubusercontent.com/jambudio336-hue/Mazkipdramabox/main/kiplay.mp4';
  static const _etagKey = 'm4zk1playdramabox_splash_etag';

  final Player _player = Player();
  late final VideoController _controller = VideoController(_player);
  StreamSubscription<bool>? _completedSubscription;
  StreamSubscription<String>? _errorSubscription;
  bool _ready = false;
  bool _finished = false;
  bool _released = false;

  @override
  void initState() {
    super.initState();
    _completedSubscription = _player.stream.completed.listen((completed) {
      if (completed) _finish();
    });
    _errorSubscription = _player.stream.error.listen((_) => _finish());
    unawaited(_prepareAndPlay());
  }

  Future<void> _prepareAndPlay() async {
    try {
      final directory = await getApplicationSupportDirectory();
      final cachedVideo = File('${directory.path}/kiplay.mp4');
      final hasCachedVideo =
          await cachedVideo.exists() && await cachedVideo.length() > 1024;
      unawaited(_refreshRemoteVideo(cachedVideo));
      await _player.open(
        Media(hasCachedVideo ? cachedVideo.path : 'asset:///kiplay.mp4'),
      );
      if (mounted && !_finished) setState(() => _ready = true);
    } catch (_) {
      _finish();
    }
  }

  Future<void> _refreshRemoteVideo(File destination) async {
    HttpClient? client;
    final temporary = File('${destination.path}.download');
    try {
      final preferences = await SharedPreferences.getInstance();
      client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
      final request = await client.getUrl(Uri.parse(_videoUrl));
      final etag = preferences.getString(_etagKey);
      if (etag != null && etag.isNotEmpty) {
        request.headers.set(HttpHeaders.ifNoneMatchHeader, etag);
      }
      final response = await request.close().timeout(
        const Duration(seconds: 20),
      );
      if (response.statusCode == HttpStatus.notModified) return;
      if (response.statusCode != HttpStatus.ok) return;
      await destination.parent.create(recursive: true);
      if (await temporary.exists()) await temporary.delete();
      await response.pipe(temporary.openWrite());
      if (!await temporary.exists() || await temporary.length() < 1024) {
        if (await temporary.exists()) await temporary.delete();
        return;
      }
      await temporary.rename(destination.path);
      final latestEtag = response.headers.value(HttpHeaders.etagHeader);
      if (latestEtag != null && latestEtag.isNotEmpty) {
        await preferences.setString(_etagKey, latestEtag);
      }
    } catch (_) {
      if (await temporary.exists()) await temporary.delete();
    } finally {
      client?.close(force: true);
    }
  }

  void _finish() {
    if (_finished || !mounted) return;
    setState(() => _finished = true);
    unawaited(_releasePlayer());
  }

  Future<void> _releasePlayer() async {
    if (_released) return;
    _released = true;
    await _player.dispose();
  }

  @override
  void dispose() {
    _completedSubscription?.cancel();
    _errorSubscription?.cancel();
    unawaited(_releasePlayer());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_finished) return widget.child;
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          if (_ready)
            Video(
              controller: _controller,
              fit: BoxFit.cover,
              controls: (_) => const SizedBox.shrink(),
            )
          else
            const Center(
              child: CircularProgressIndicator(color: Color(0xFFFF765F)),
            ),
          const Positioned(
            left: 24,
            right: 24,
            bottom: 54,
            child: Text(
              'M4zk1pL4yDramaBox',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.1,
                shadows: [Shadow(color: Colors.black87, blurRadius: 12)],
              ),
            ),
          ),
          Positioned(
            top: MediaQuery.paddingOf(context).top + 12,
            right: 16,
            child: TextButton(
              onPressed: _finish,
              style: TextButton.styleFrom(
                foregroundColor: Colors.white,
                backgroundColor: Colors.black54,
              ),
              child: const Text('Lewati'),
            ),
          ),
        ],
      ),
    );
  }
}
