import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:untitled/tv_util.dart';
import 'package:chewie/chewie.dart';
import 'package:video_player/video_player.dart';

import 'widget/tv_widget.dart';

void main() {
  runApp(const TvApp());
}

class TvApp extends StatelessWidget {
  const TvApp({super.key});

  @override
  Widget build(BuildContext context) {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual, overlays: []);

    return const MaterialApp(
      home: HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<StatefulWidget> createState() {
    return _HomePage();
  }
}

class _HomePage extends State<StatefulWidget> {
  List<ChannelGroup> groups = [];

  late ChewieController _chewieController;
  late VideoPlayerController _videoPlayerController;
  late Channel currentChannel;
  bool hasInit = false;
  bool _showListView = false;

  @override
  void initState() {
    super.initState();

    initData();
  }

  initData() async {
    var data = await TvUtil.fetchData();
    setState(() {
      groups = data;
      var c = groups[0].children[0];

      if (c.url != "") {
        changeChannel(c);
        hasInit = true;
      }
    });
  }

  changeChannel(Channel c) {
    _showListView = false;

    currentChannel = c;

    _videoPlayerController =
        VideoPlayerController.networkUrl(Uri.parse(currentChannel.url));
    _chewieController = ChewieController(
      videoPlayerController: _videoPlayerController,
      autoPlay: true,
      looping: false,
      autoInitialize: true,
      aspectRatio: MediaQuery.of(context).devicePixelRatio,
      showControls: false,
    );
  }

  @override
  Widget build(BuildContext context) {
    // 获取屏幕宽度
    double screenWidth = MediaQuery.of(context).size.width;

    // 获取屏幕高度
    double screenHeight = MediaQuery.of(context).size.height;

    return Scaffold(
      body: Center(
          child: Container(
        color: Colors.black,
        child: Stack(
          children: [
            hasInit
                ? Chewie(controller: _chewieController)
                : const Text("初始化中"),
            // 透明的组件
            TVWidget(
              key: Key('1'),
              focusChange: (bool hasFocus) {  },
              onclick: () {
                setState(() {
                  _showListView = true;
                });
              },
              decoration: const BoxDecoration(
                color: Colors.transparent
              ),
              onup: () {  },
              ondown: () {  },
              onback: () {  },
              child: Align(
                alignment: Alignment.center,
                child: InkWell(
                  child: GestureDetector(
                    onTap: () {
                      setState(() {
                        _showListView = true;
                      });
                    },
                    child: Container(
                      color: Colors.transparent,
                      width: screenWidth / 3,
                      height: screenHeight / 3,
                    ),
                  ),
                ),
              ),
            ),
            // 遮罩
            if (_showListView)
              Align(
                alignment: Alignment.center,
                child: GestureDetector(
                  onTap: () {
                    setState(() {
                      _showListView = false;
                    });
                  },
                  child: AnimatedOpacity(
                    opacity: _showListView ? 0.5 : 0.0, // 控制遮罩的透明度
                    duration: const Duration(milliseconds: 500), // 动画持续时间
                    child: Container(
                      color: Colors.white, // 遮罩颜色
                    ),
                  ),
                ),
              ),
            AnimatedPositioned(
                duration: const Duration(milliseconds: 250),
                // 动画持续时间
                left: _showListView ? 0 : -200,
                // 控制ListView的位置
                top: 0,
                bottom: 0,
                width: 200,
                // 控制ListView的宽度
                child: Container(
                    color: Colors.black.withOpacity(0.4), // ListView背景颜色
                    child: ListView.builder(
                      itemCount: groups.length,
                      itemBuilder: (context, index) {
                        final group = groups[index];
                        return Column(
                          children: group.children.map((child) {
                            return TVWidget(
                                key: Key(child.name),
                                focusChange: (bool hasFocus) {
                                  print("focusChange");
                                },
                                onclick: () {
                                  print("click");
                                  setState(() {
                                    if (!_showListView) {
                                      _showListView = true;
                                    } else {
                                      changeChannel(child);
                                    }
                                  });
                                },
                                decoration: const BoxDecoration(
                                  color: Colors.amber
                                ),
                                onup: () {  },
                                ondown: () {  },
                                onback: () {  },
                                child: Row(
                              children: [
                                const SizedBox(width: 10.0), // 用于添加间距

                                    Image.network(
                                  child.logo,
                                  width: 50.0, // 图片宽度
                                  height: 20.0, // 图片高度
                                  fit: BoxFit.cover, // 图片适应方式
                                ),

                                Expanded(
                                    child: ListTile(
                                  title: Text(
                                    child.name,
                                    style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold),
                                  ),
                                  onTap: () {
                                    setState(() {
                                      changeChannel(child);
                                    });
                                  },
                                ))
                              ],
                            ));
                          }).toList(),
                        );
                      },
                    )))
          ],
        ),
      )),
    );
  }
}
