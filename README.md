# 电视直播 IPTV

## 支持安卓手机、安卓平板、iOS、安卓TV 等设备，理论上也支持 ipad， appleTv 没有做适配

## 使用方式

### 触屏设备 手机 / pad 等

![phone-1.png](source%2Fphone-1.png)


1. 点击屏幕中间调出左侧频道选择菜单
2. 点击频道名字换台

### 非触屏设备（电视）
![tv-1.png](source%2Ftv-1.png)

1. 按 确认 / 上 / 下 键 调出左侧频道菜单
2. 使用 上 / 下 键进行频道选择
3. 再次按 确认 键换台
4. 连续两次按返回键退出app

### 数据来源
1. 所有直播频道数据都来源于网络，侵权请联系删除
2. **频道列表已内置在 `assets/tv.json`，启动时不请求任何服务器**（原实现会请求 `https://tv.huandreamer.top/`，已移除）。换频道列表直接改这个文件，格式不变
3. 频道列表的 `version` / `url` 字段用于自动升级：`version` 与 `lib/main.dart` 里的 `appVersion` 不同且 `url` 非空时，会下载该 url 的 APK 并拉起安装。不想要自动升级就把 `url` 留空
4. 仅供学习交流，切勿用于商用，本人不对任何后果负责

## 目录结构

```
lib/main.dart            播放页：频道列表、遥控器按键、换台、自动升级
lib/tv_util.dart         读取并解析内置频道列表
lib/tv_toast.dart        轻提示封装
assets/tv.json           内置频道列表（45 个频道）
images/logo.png          应用图标素材
test/widget_test.dart    注入假播放器，覆盖加载/失败/超时/换台释放等路径
android/ ios/            平台工程
```

## 构建环境

- Flutter 3.13+（stable），Dart 3.1+
- Android：**JDK 11 或更高**（AGP 7.3 要求，JDK 8 会直接构建失败；本机用 JDK 18 验证）；
  需 Android SDK Platform 34（`video_player_android` 要求），`android/app/build.gradle`
  已显式写 `compileSdkVersion 34`
- iOS：CocoaPods。注意本机 CocoaPods 是 x86_64 安装的，Apple Silicon 上要
  `arch -x86_64 pod install`，否则会报 ffi 架构不匹配

如果构建报 `flutter.sdk not set in local.properties`，说明 `android/local.properties`
缺失（该文件已不再入库，属于本机配置），在项目根执行一次 `flutter pub get` 会重新生成。

## 已知说明

- 频道地址多为明文 `http://`，因此 Android manifest 开了 `usesCleartextTraffic`，
  iOS `Info.plist` 开了 `NSAllowsArbitraryLoads`
- 部分频道是 IPv6 源，网络不支持 IPv6 时该频道会播放失败，可通过左右键换台
- 某个频道源失效时会显示失败原因和「重试」，不会卡在加载中