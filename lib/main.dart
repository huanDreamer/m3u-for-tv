import 'dart:async';
import 'dart:io';

import 'package:chewie/chewie.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:install_plugin/install_plugin.dart';
import 'package:path_provider/path_provider.dart';
import 'package:tv/tv_toast.dart';
import 'package:tv/tv_util.dart';
import 'package:video_player/video_player.dart';
import 'package:wakelock/wakelock.dart';

/// 当前 App 版本，与内置频道列表里的 version 比较以判断是否需要升级。
const String appVersion = "1.0";

/// 单个频道初始化超时。
///
/// 直播源不可达时底层播放器可能一直不回调，靠这个兜底，避免界面永远停在加载中。
const Duration kInitTimeout = Duration(seconds: 20);

/// 遥控器按键的去抖间隔，避免一次长按触发多次换台。
const Duration kKeyDebounce = Duration(milliseconds: 300);

void main() {
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual, overlays: []);

  Wakelock.enable();

  WidgetsFlutterBinding.ensureInitialized();

  runApp(const TvApp());
}

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
  const HomePage({super.key, this.loader, this.initTimeout = kInitTimeout});

  /// 频道列表加载器。默认读取内置 asset，测试里注入假实现以驱动失败路径。
  final Future<ChannelResponse> Function()? loader;

  /// 单个频道初始化超时，测试里可以调小以避免等待。
  final Duration initTimeout;

  @override
  State<HomePage> createState() {
    return _HomePage();
  }
}

/// 频道列表的加载状态。原先只用 hasInit 布尔值区分，失败时无法与「正在加载」区分，
/// 界面会永远停在「初始化中」。
enum _LoadState { loading, ready, failed }

class _HomePage extends State<HomePage> {
  List<Channel> channels = [];

  /// 播放器在初始化完成前为 null；用可空字段代替 late，
  /// 避免未初始化就 dispose 时抛 LateInitializationError。
  VideoPlayerController? _videoPlayerController;
  ChewieController? _chewieController;

  Channel? currentChannel;
  int currentIdx = 0;
  int focusIdx = 0;
  bool _showListView = false;

  _LoadState _loadState = _LoadState.loading;
  String? _loadError;

  /// 播放阶段的错误（换台失败、流中断），与 [_loadError] 分开：
  /// 前者只影响播放区，后者意味着整个列表都没读到。
  String? _playError;

  /// 每次换台递增。异步初始化返回时若代次已变，说明用户又换了台，
  /// 这一次的结果必须丢弃，否则会把旧频道的错误盖到新频道上。
  int _generation = 0;

  final ScrollController _listViewController = ScrollController();

  /// 原先每帧 build 都新建一个 FocusNode，既不生效也会泄漏，改为持有单例。
  final FocusNode _focusNode = FocusNode();

  // 退出
  DateTime _lastBackPressedTime = DateTime.now();
  DateTime _lastClick = DateTime.now();

  @override
  void initState() {
    super.initState();

    initData();
  }

  @override
  void dispose() {
    // 让仍在进行中的初始化结果失效，并释放播放器。
    _generation++;
    _releasePlayer();
    _listViewController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  /// 读取内置频道列表并播放第一个频道。
  ///
  /// 频道列表来自打包进 App 的 assets/tv.json，不发任何网络请求。
  Future<void> initData() async {
    if (mounted) {
      setState(() {
        _loadState = _LoadState.loading;
        _loadError = null;
        _playError = null;
      });
    }

    final ChannelResponse data;
    try {
      data = await (widget.loader ?? TvUtil.fetchData)();
    } on ChannelLoadException catch (e) {
      _setLoadFailed(e.message);
      return;
    } catch (e) {
      _setLoadFailed('读取频道列表失败：$e');
      return;
    }

    if (!mounted) {
      return;
    }

    // 升级：仅在列表声明的版本与当前版本不同、且带下载地址时才触发。
    if (data.url.isNotEmpty && data.version != appVersion) {
      doUpdate(data.url);
    }

    if (data.children.isEmpty) {
      _setLoadFailed('内置频道列表为空');
      return;
    }

    channels = data.children;
    focusIdx = 0;
    setState(() {
      _loadState = _LoadState.ready;
    });

    await changeChannel();
  }

  void _setLoadFailed(String message) {
    if (!mounted) {
      return;
    }
    setState(() {
      _loadState = _LoadState.failed;
      _loadError = message;
    });
  }

  // app升级
  Future<void> doUpdate(String url) async {
    TvToast.show("发现新版本,正在升级");

    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        final Directory tempDir = await getTemporaryDirectory();
        final String tempPath = tempDir.path;

        File file = File('$tempPath/tv.apk');
        await file.writeAsBytes(response.bodyBytes);

        InstallPlugin.installApk(file.path);
      } else {
        TvToast.show("下载失败");
      }
    } catch (e) {
      TvToast.show('安装失败:$e');
    }
  }

  /// 切换到 [focusIdx] 指向的频道。
  Future<void> changeChannel() async {
    if (channels.isEmpty) {
      return;
    }
    if (focusIdx < 0 || focusIdx >= channels.length) {
      focusIdx = 0;
    }

    _showListView = false;
    final channel = channels[focusIdx];
    currentChannel = channel;
    currentIdx = focusIdx;

    await _openUrl(channel.url);
  }

  /// 打开一个地址播放：先释放上一个播放器，再重建。
  Future<void> _openUrl(String url) async {
    final generation = ++_generation;
    // 换台时必须先释放旧的播放器，否则每次换台都会残留一个仍在缓冲的播放器。
    _releasePlayer();

    if (mounted) {
      setState(() {
        _playError = null;
      });
    }

    final uri = Uri.tryParse(url);
    if (uri == null || !uri.hasScheme) {
      if (mounted && generation == _generation) {
        setState(() {
          _playError = '播放地址无效：$url';
        });
      }
      return;
    }

    final player = VideoPlayerController.networkUrl(uri);

    // 自己 await initialize()，把失败收敛成界面上的提示。
    // 依赖 chewie 的 autoInitialize 的话，异常会在它构造函数里发射后不管的
    // _initialize() 中变成未捕获的异步异常，界面只会一直转圈。
    try {
      await player.initialize().timeout(widget.initTimeout);
    } on TimeoutException {
      _disposeSafely(player);
      if (mounted && generation == _generation) {
        setState(() {
          _playError = '连接超时：${currentChannel?.name ?? url}，请换一个频道。';
        });
      }
      return;
    } catch (e) {
      _disposeSafely(player);
      if (mounted && generation == _generation) {
        setState(() {
          _playError = '无法播放 ${currentChannel?.name ?? url}：$e';
        });
      }
      return;
    }

    // 初始化期间用户又换了台或页面已销毁，这次的结果作废。
    if (!mounted || generation != _generation) {
      _disposeSafely(player);
      return;
    }

    final chewie = ChewieController(
      videoPlayerController: player,
      autoInitialize: false, // 上面已经初始化过了
      autoPlay: true,
      looping: false,
      aspectRatio: 16 / 9.0,
      showControls: false,
    );

    player.addListener(_onPlayerChanged);
    setState(() {
      _videoPlayerController = player;
      _chewieController = chewie;
    });
  }

  /// 释放当前播放器。
  ///
  /// chewie 的 [ChewieController] 没有重写 dispose()，底层 [VideoPlayerController]
  /// 必须由调用方释放，否则会残留仍在缓冲的播放器。
  void _releasePlayer() {
    final player = _videoPlayerController;
    final chewie = _chewieController;
    _videoPlayerController = null;
    _chewieController = null;

    if (player != null) {
      player.removeListener(_onPlayerChanged);
      _disposeSafely(player);
    }
    chewie?.dispose();
  }

  /// 释放播放器且不等待结果。
  ///
  /// 不能 await：video_player 在 create() 抛错时不会完成内部的 _creatingCompleter，
  /// dispose() 会一直挂着，await 它会让后面的 setState 永远执行不到，
  /// 界面卡在加载中。create() 失败时平台侧也没分配资源，不等待不会泄漏。
  void _disposeSafely(VideoPlayerController player) {
    unawaited(player.dispose().catchError((Object _) {}));
  }

  /// 播放中途出错（流断开等）时切到错误提示。
  void _onPlayerChanged() {
    final player = _videoPlayerController;
    if (player == null || !mounted) {
      return;
    }

    final value = player.value;
    if (value.hasError) {
      final message = value.errorDescription ?? '播放中断，未知错误';
      if (_playError == message) {
        return;
      }
      setState(() {
        _playError = message;
      });

      // 这里不能同步 dispose：本方法由 notifyListeners() 触发，
      // 而 ChangeNotifier.dispose() 断言不能在通知过程中被调用。
      scheduleMicrotask(() {
        if (!mounted) {
          return;
        }
        _releasePlayer();
      });
      return;
    }
  }

  void focusChange(int add) {
    if (channels.isEmpty) {
      return;
    }
    focusIdx += add;
    if (focusIdx < 0) {
      focusIdx = channels.length - 1;
    }
    if (focusIdx >= channels.length) {
      focusIdx = 0;
    }
    if (_listViewController.hasClients) {
      // 目标偏移可能为负（列表顶部附近），animateTo 传负值会触发越界回弹，这里夹到 0。
      final target = 50.0 * getShowIdx();
      _listViewController.animateTo(
        target < 0 ? 0 : target,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeInOut,
      );
    }
  }

  void showList(bool show) {
    if ((show && _showListView) || (!show && !_showListView)) {
      return;
    }
    _showListView = show;
    if (_showListView) {
      focusChange(currentIdx - focusIdx);
    }
  }

  int getShowIdx() {
    return focusIdx - 4;
  }

  @override
  Widget build(BuildContext context) {
    // 获取屏幕宽度
    double screenWidth = MediaQuery.of(context).size.width;

    // 获取屏幕高度
    double screenHeight = MediaQuery.of(context).size.height;

    return RawKeyboardListener(
      focusNode: _focusNode,
      autofocus: true,
      onKey: _onKey,
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
              TvToast.show("再按一次退出应用");
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
                _buildVideoArea(),
                // 透明的组件
                Align(
                  alignment: Alignment.center,
                  child: GestureDetector(
                    key: const Key('open-channel-list'),
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
                                        return const SizedBox(width: 1.0);
                                      },
                                    ),

                                  Expanded(
                                      child: ListTile(
                                    title: Text(
                                      child.name,
                                      style: TextStyle(
                                          color:
                                              currentChannel?.url == child.url ||
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

  /// 播放区：正常时是播放器，加载中显示进度，失败时显示原因和重试入口。
  Widget _buildVideoArea() {
    final chewie = _chewieController;
    if (chewie != null) {
      return Chewie(controller: chewie);
    }

    if (_loadState == _LoadState.failed) {
      return _buildMessage(
        _loadError ?? '频道列表加载失败',
        action: TextButton(
          onPressed: () {
            initData();
          },
          child: const Text('重试'),
        ),
      );
    }

    final playError = _playError;
    if (playError != null) {
      return _buildMessage(
        playError,
        action: TextButton(
          onPressed: () {
            changeChannel();
          },
          child: const Text('重试'),
        ),
      );
    }

    return const Center(child: CircularProgressIndicator());
  }

  Widget _buildMessage(String message, {Widget? action}) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white),
            ),
            if (action != null) action,
          ],
        ),
      ),
    );
  }

  /// 遥控器按键处理。
  ///
  /// 原实现直接 `key.data as RawKeyEventDataAndroid`，在非 Android 平台
  /// （iOS/桌面）会抛类型转换异常，这里改成先判断类型。
  void _onKey(RawKeyEvent key) {
    if (DateTime.now().difference(_lastClick) < kKeyDebounce) {
      return;
    }
    _lastClick = DateTime.now();

    final data = key.data;
    if (data is! RawKeyEventDataAndroid) {
      return;
    }

    switch (data.keyCode) {
      case 23:
      case 66:
        if (!_showListView) {
          showList(true);
        } else {
          changeChannel();
        }
        break;
      case 20: // 下
        if (!_showListView) {
          showList(true);
        } else {
          focusChange(1);
        }
        break;
      case 19: // 上
        if (!_showListView) {
          showList(true);
        } else {
          focusChange(-1);
        }
        break;
    }
    setState(() {});
  }
}
