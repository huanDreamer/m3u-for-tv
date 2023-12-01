import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:tv/tv_util.dart';
import 'package:chewie/chewie.dart';
import 'package:video_player/video_player.dart';
import 'package:uuid/uuid.dart';
import 'package:wakelock/wakelock.dart';
import 'package:flutter_downloader/flutter_downloader.dart';

void main() {
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual, overlays: []);

  Wakelock.enable();

  // 初始化 flutter_downloader
  WidgetsFlutterBinding.ensureInitialized();
  FlutterDownloader.initialize(
      debug: true // 是否为调试模式
  );

  runApp(const TvApp());
}

String appVersion = "1.0";

class TvApp extends StatelessWidget {
  const TvApp({super.key});

  @override
  Widget build(BuildContext context) {

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
  List<Channel> channels = [];

  late ChewieController _chewieController;
  late VideoPlayerController _videoPlayerController;
  late Channel currentChannel;
  int currentIdx = 0;
  int focusIdx = 0;
  bool hasInit = false;
  bool _showListView = false;

  final ScrollController _listViewController = ScrollController();

  // 退出
  DateTime _lastBackPressedTime = DateTime.now();
  DateTime _lastClick = DateTime.now();

  var uuid = Uuid();

  @override
  void initState() {
    super.initState();

    initData();
  }

  initData() async {
    var data = await TvUtil.fetchData();

    // 升级
    if (data.version != appVersion && data.url != "") {
      await doUpdate(data.url);
    }

    channels = data.children;
    if (channels.isNotEmpty) {
      focusIdx = 0;
      changeChannel();
      hasInit = true;
    }

    setState(() {});
  }

  // app升级
  doUpdate(String url) async {

    url = "https://r2.huandreamer.top/tv.apk";

    await FlutterDownloader.enqueue(
      url: url,
      savedDir: '/storage/emulated/0/Download/',
      showNotification: true,
      saveInPublicStorage: true,
      openFileFromNotification: true,
      requiresStorageNotLow: true, // 确保只在存储空间充足时才会下载
    );


    Fluttertoast.showToast(
      msg: '发现新版本正在升级',
      toastLength: Toast.LENGTH_SHORT,
      gravity: ToastGravity.BOTTOM,
      timeInSecForIosWeb: 2,
    );

  }

  changeChannel() {
    print('--------- channelchange${channels[focusIdx].name}');

    _showListView = false;
    currentChannel = channels[focusIdx];
    currentIdx = focusIdx;

    _videoPlayerController =
        VideoPlayerController.networkUrl(Uri.parse(currentChannel.url));

    _chewieController = ChewieController(
      videoPlayerController: _videoPlayerController,
      autoPlay: true,
      looping: false,
      autoInitialize: true,
      // aspectRatio: MediaQuery.of(context).devicePixelRatio,
      aspectRatio: 16 / 9.0,
      showControls: false,
    );
  }

  focusChange(int add) {
    focusIdx += add;
    if (focusIdx < 0) {
      focusIdx = channels.length - 1;
    }
    if (focusIdx >= channels.length) {
      focusIdx = 0;
    }
    _listViewController.animateTo(
      50.0 * getShowIdx(),
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeInOut, // 滚动的动画曲线
    );
  }

  showList(bool show) {
    if ((show && _showListView) || (!show && !_showListView)) {
      return;
    }
    _showListView = show;
    if (_showListView) {
      focusChange(currentIdx - focusIdx);
    }
  }

  int getShowIdx() {
    // print('focus: ${focusIdx}');
    // if (focusIdx < 4) {
    //   return 0;
    // }
    return focusIdx - 4;
  }

  @override
  Widget build(BuildContext context) {
    // 获取屏幕宽度
    double screenWidth = MediaQuery.of(context).size.width;

    // 获取屏幕高度
    double screenHeight = MediaQuery.of(context).size.height;

    return RawKeyboardListener(
      focusNode: FocusNode(),
      autofocus: true,
      onKey: (key) {
        if (DateTime.now().difference(_lastClick) <
            const Duration(milliseconds: 300)) {
          print('重复点击');
          return;
        }
        RawKeyEventDataAndroid event = key.data as RawKeyEventDataAndroid;
        switch (event.keyCode) {
          case 23:
          case 66:
            if (!_showListView) {
              showList(true);
            } else {
              changeChannel();
            }
            break;
          case 20: // 下
            print("下");
            if (!_showListView) {
              showList(true);
            } else {
              focusChange(1);
            }
            break;
          case 19: // 上
            print("上");
            if (!_showListView) {
              showList(true);
            } else {
              focusChange(-1);
            }
            break;
        }
        _lastClick = DateTime.now();
        setState(() {});
      },
      child: WillPopScope(
        onWillPop: () async {
          if (_showListView) {
            setState(() {
              showList(false);
            });
            return false;
          } else {
            if (DateTime.now().difference(_lastBackPressedTime) >=
                const Duration(seconds: 2)) {
              _lastBackPressedTime = DateTime.now();
              Fluttertoast.showToast(
                msg: '再按一次退出应用',
                toastLength: Toast.LENGTH_SHORT,
                gravity: ToastGravity.BOTTOM,
                timeInSecForIosWeb: 2,
              );
              return false;
            } else {
              return true;
            }
          }
        },
        child: Scaffold(
          body: Center(
              child: Container(
            color: Colors.black,
            child: Stack(
              children: [
                hasInit
                    ? Chewie(controller: _chewieController)
                    : const Text("初始化中"),
                // 透明的组件
                Align(
                  alignment: Alignment.center,
                  child: GestureDetector(
                    onTap: () {
                      setState(() {
                        showList(true);
                      });
                    },
                    child: Container(
                      color: Colors.transparent,
                      width: screenWidth / 2,
                      height: screenHeight / 2,
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
                          showList(false);
                        });
                      },
                      child: AnimatedOpacity(
                        opacity: _showListView ? 0.5 : 0.0,
                        // 控制遮罩的透明度
                        duration: const Duration(milliseconds: 500),
                        // 动画持续时间
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
                        color: Colors.black.withOpacity(0.4),
                        // ListView背景颜色
                        child: ListView.builder(
                            itemCount: channels.length,
                            itemExtent: 50.0,
                            controller: _listViewController,
                            itemBuilder: (context, index) {
                              final child = channels[index];
                              return Row(
                                children: [
                                  const SizedBox(width: 10.0), // 用于添加间距
                                  if (child.logo != "")
                                    Image.network(
                                      child.logo,
                                      width: 50.0, // 图片宽度
                                      fit: BoxFit.cover, // 图片适应方式
                                      errorBuilder: (ctx, err, s) {
                                        return SizedBox(width: 1.0);
                                      },
                                    ),

                                  Expanded(
                                      child: ListTile(
                                    title: Text(
                                      child.name,
                                      style: TextStyle(
                                          color:
                                              currentChannel.url == child.url ||
                                                      focusIdx == index
                                                  ? Colors.amber
                                                  : Colors.white,
                                          fontWeight: FontWeight.bold),
                                    ),
                                    onTap: () {
                                      focusIdx = index;
                                      changeChannel();
                                      setState(() {});
                                    },
                                  ))
                                ],
                              );
                            })))
              ],
            ),
          )),
        ),
      ),
    );
  }

  @override
  void dispose() {
    // 在页面销毁时释放资源
    _videoPlayerController.dispose();
    _chewieController.dispose();
    super.dispose();
  }
}
