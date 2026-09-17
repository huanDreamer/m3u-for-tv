import 'dart:async';

import 'package:chewie/chewie.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tv/main.dart';
import 'package:tv/tv_util.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

/// 假的底层播放器实现，用来在测试里驱动真实播放路径，
/// 不依赖任何平台插件或网络。
class _FakeVideoPlayerPlatform extends VideoPlayerPlatform {
  _FakeVideoPlayerPlatform({this.failWith, this.neverInitializes = false});

  /// 非空时，create() 抛出该错误，模拟地址不可用。
  final PlatformException? failWith;

  /// 为 true 时只创建不回调初始化事件，模拟卡住不返回。
  final bool neverInitializes;

  // 必须是单订阅流：video_player 是先 create() 拿到 textureId、
  // 再去 listen，广播流会把这段间隙里发出的事件丢掉。
  final Map<int, StreamController<VideoEvent>> _events = {};
  int _nextTextureId = 1;
  final List<String> createdUris = [];

  /// 被释放过的 textureId 数量，用来验证换台时旧播放器确实被释放。
  int disposedCount = 0;

  @override
  Future<void> init() async {}

  @override
  Future<int?> create(DataSource dataSource) async {
    createdUris.add(dataSource.uri ?? '');
    if (failWith != null) {
      throw failWith!;
    }
    final id = _nextTextureId++;
    final controller = StreamController<VideoEvent>();
    _events[id] = controller;
    if (!neverInitializes) {
      // 用单订阅流缓冲事件，等 video_player 真正 listen 时再补发，
      // 贴近真实插件「先创建、后订阅」的行为。
      controller.add(VideoEvent(
        eventType: VideoEventType.initialized,
        duration: const Duration(seconds: 10),
        size: const Size(1280, 720),
      ));
    }
    return id;
  }

  @override
  Stream<VideoEvent> videoEventsFor(int textureId) =>
      _events[textureId]?.stream ?? const Stream<VideoEvent>.empty();

  @override
  Future<void> dispose(int textureId) async {
    disposedCount++;
    await _events.remove(textureId)?.close();
  }

  @override
  Future<void> setLooping(int textureId, bool looping) async {}

  @override
  Future<void> play(int textureId) async {}

  @override
  Future<void> pause(int textureId) async {}

  @override
  Future<void> setVolume(int textureId, double volume) async {}

  @override
  Future<void> setPlaybackSpeed(int textureId, double speed) async {}

  @override
  Future<void> seekTo(int textureId, Duration position) async {}

  @override
  Future<Duration> getPosition(int textureId) async => Duration.zero;

  @override
  Widget buildView(int textureId) => const SizedBox.shrink();

  @override
  Future<void> setMixWithOthers(bool mixWithOthers) async {}
}

/// 构造一个不会触发自动升级的频道列表：
/// version 与 appVersion 一致、url 为空，避免测试里发真实网络请求。
ChannelResponse _channels(List<Channel> channels) =>
    ChannelResponse(version: appVersion, url: '', children: channels);

final _cctv1 = Channel(
  name: 'CCTV1',
  logo: '',
  url: 'https://example.com/cctv1.m3u8',
);
final _cctv2 = Channel(
  name: 'CCTV2',
  logo: '',
  url: 'https://example.com/cctv2.m3u8',
);

/// 反复 pump 直到 [finder] 命中或超过 [maxPumps] 次。
///
/// 播放器初始化要走 create() -> listen -> 事件回调 好几轮事件循环，
/// 数固定帧数很容易踩空；加载态的 CircularProgressIndicator 又是永动动画，
/// 所以也不能用 pumpAndSettle。
Future<void> _pumpUntil(
  WidgetTester tester,
  Finder finder, {
  int maxPumps = 30,
  Duration step = const Duration(milliseconds: 50),
}) async {
  for (var i = 0; i < maxPumps; i++) {
    await tester.pump(step);
    if (finder.evaluate().isNotEmpty) {
      return;
    }
  }
}

/// 等待 [condition] 成立。
///
/// [VideoPlayerController.dispose] 内部要 await 平台侧释放的结果，只靠 pump
/// 推进 fake 时钟不够，必须用 [WidgetTester.runAsync] 让真实事件循环跑起来。
Future<void> _waitFor(
  WidgetTester tester,
  bool Function() condition, {
  int maxTries = 30,
}) async {
  for (var i = 0; i < maxTries; i++) {
    if (condition()) {
      return;
    }
    await tester.pump(const Duration(milliseconds: 20));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
  }
  await tester.pump();
}

void main() {
  group('HomePage 播放流程', () {
    testWidgets('频道列表加载成功后播放第一个频道', (WidgetTester tester) async {
      final fake = _FakeVideoPlayerPlatform();
      VideoPlayerPlatform.instance = fake;

      await tester.pumpWidget(MaterialApp(
        home: HomePage(loader: () async => _channels([_cctv1, _cctv2])),
      ));
      await _pumpUntil(tester, find.byType(Chewie));

      // 播放的是列表里第一个频道的地址。
      expect(fake.createdUris, [_cctv1.url]);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text('重试'), findsNothing);
    });

    testWidgets('加载器失败时显示原因和重试，而不是停在初始化中',
        (WidgetTester tester) async {
      VideoPlayerPlatform.instance = _FakeVideoPlayerPlatform();

      await tester.pumpWidget(MaterialApp(
        home: HomePage(
          loader: () async => throw ChannelLoadException('读取内置频道列表失败'),
        ),
      ));
      await tester.pump();

      expect(find.textContaining('读取内置频道列表失败'), findsOneWidget);
      expect(find.text('重试'), findsOneWidget);
      expect(find.text('初始化中'), findsNothing);
    });

    testWidgets('频道列表为空时给出明确提示', (WidgetTester tester) async {
      VideoPlayerPlatform.instance = _FakeVideoPlayerPlatform();

      await tester.pumpWidget(MaterialApp(
        home: HomePage(loader: () async => _channels([])),
      ));
      await tester.pump();

      expect(find.textContaining('内置频道列表为空'), findsOneWidget);
      expect(find.text('重试'), findsOneWidget);
    });

    testWidgets('地址不可用时显示错误而不是崩溃', (WidgetTester tester) async {
      // initialize() 失败在 video_player 里是 completeError，
      // 修好之前这里会变成未捕获的异步异常。
      VideoPlayerPlatform.instance = _FakeVideoPlayerPlatform(
        failWith: PlatformException(code: 'VideoError', message: '网络不可达'),
      );

      await tester.pumpWidget(MaterialApp(
        home: HomePage(loader: () async => _channels([_cctv1])),
      ));
      await _pumpUntil(tester, find.textContaining('无法播放'));

      expect(find.textContaining('无法播放 CCTV1'), findsOneWidget);
      expect(find.textContaining('网络不可达'), findsOneWidget);
      expect(find.text('重试'), findsOneWidget);
    });

    testWidgets('初始化卡住时超时并提示重试', (WidgetTester tester) async {
      VideoPlayerPlatform.instance =
          _FakeVideoPlayerPlatform(neverInitializes: true);

      await tester.pumpWidget(MaterialApp(
        home: HomePage(
          loader: () async => _channels([_cctv1]),
          initTimeout: const Duration(milliseconds: 100),
        ),
      ));
      await tester.pump();

      // 超时之前：仍处于加载中。
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      // 推进到超过超时时间，触发 TimeoutException 分支。
      await _pumpUntil(
        tester,
        find.textContaining('连接超时'),
        step: const Duration(milliseconds: 100),
      );

      expect(find.textContaining('连接超时'), findsOneWidget);
      expect(find.text('重试'), findsOneWidget);
    });

    testWidgets('换台会释放上一个播放器并播放新频道', (WidgetTester tester) async {
      final fake = _FakeVideoPlayerPlatform();
      VideoPlayerPlatform.instance = fake;

      await tester.pumpWidget(MaterialApp(
        home: HomePage(loader: () async => _channels([_cctv1, _cctv2])),
      ));
      await _pumpUntil(tester, find.byType(Chewie));

      // 打开频道列表。用 Key 定位透明触发区：列表本身一直挂在树上，
      // 只是被 AnimatedPositioned 移到屏幕外，按类型取会点到错误的 GestureDetector。
      await tester.tap(find.byKey(const Key('open-channel-list')));
      await tester.pumpAndSettle();

      // 点击第二个频道。
      await tester.tap(find.text('CCTV2'));

      // 等旧播放器被释放（修复前换台根本不 dispose，这里会一直是 0）。
      await _waitFor(tester, () => fake.disposedCount > 0);

      expect(fake.createdUris, [_cctv1.url, _cctv2.url]);
      expect(fake.disposedCount, 1);
    });
  });

  group('TvUtil 频道列表解析', () {
    test('解析正常列表', () {
      final data = TvUtil.parse('''
      {
        "version": "1.2",
        "url": "https://example.com/tv.apk",
        "children": [
          {"name": "CCTV1", "logo": "", "url": "https://example.com/1.m3u8"}
        ]
      }
      ''');

      expect(data.version, '1.2');
      expect(data.url, 'https://example.com/tv.apk');
      expect(data.children.single.name, 'CCTV1');
    });

    test('缺失 version/url 时容错，不影响频道解析', () {
      final data = TvUtil.parse('''
      {"children": [{"name": "CCTV1", "url": "https://example.com/1.m3u8"}]}
      ''');

      expect(data.version, '');
      expect(data.url, '');
      expect(data.children.single.logo, '');
    });

    test('丢弃播放地址为空的频道', () {
      final data = TvUtil.parse('''
      {"children": [
        {"name": "空", "url": ""},
        {"name": "正常", "url": "https://example.com/1.m3u8"}
      ]}
      ''');

      expect(data.children.map((c) => c.name), ['正常']);
    });

    test('非法 JSON 抛出 ChannelLoadException 而不是 FormatException', () {
      expect(
        () => TvUtil.parse('{ not json'),
        throwsA(isA<ChannelLoadException>()),
      );
    });

    test('根节点不是对象时抛出 ChannelLoadException', () {
      expect(
        () => TvUtil.parse('[1, 2, 3]'),
        throwsA(isA<ChannelLoadException>()),
      );
    });
  });
}
