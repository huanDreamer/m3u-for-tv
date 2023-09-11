import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:chewie/chewie.dart';



class VideoPlayerPage extends StatefulWidget {
  @override
  _VideoPlayerPageState createState() => _VideoPlayerPageState();
}

class _VideoPlayerPageState extends State<VideoPlayerPage> {
  late VideoPlayerController _videoPlayerController;
  late ChewieController _chewieController;
  TextEditingController _urlController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _videoPlayerController = VideoPlayerController.network('');
    _chewieController = ChewieController(
      videoPlayerController: _videoPlayerController,
      autoPlay: false,
      looping: false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Video Player Page'),
      ),
      body: SingleChildScrollView(
        child: Column(
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: TextField(
                controller: _urlController,
              ),
            ),
            ElevatedButton(
              onPressed: () {
                _chewieController.dispose();
                _videoPlayerController = VideoPlayerController.network(_urlController.text);
                _chewieController = ChewieController(
                  videoPlayerController: _videoPlayerController,
                  autoPlay: true,
                  looping: false,
                );
                setState(() {});
              },
              child: const Text('播放'),
            ),
            Chewie(controller: _chewieController),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    super.dispose();
    _videoPlayerController.dispose();
    _chewieController.dispose();
    _urlController.dispose();
  }
}