import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

/// 频道列表改为读取打包进 App 的本地 asset，不再请求远程接口。
///
/// 原实现会 http.get("https://tv.huandreamer.top/")，现在离线可用。
const String kChannelAssetPath = 'assets/tv.json';

/// 频道列表加载失败时抛出，由调用方决定如何提示用户。
class ChannelLoadException implements Exception {
  ChannelLoadException(this.message);

  final String message;

  @override
  String toString() => message;
}

class TvUtil {
  /// 读取内置频道列表。解析或读取失败时抛 [ChannelLoadException]。
  static Future<ChannelResponse> fetchData() async {
    final String raw;
    try {
      raw = await rootBundle.loadString(kChannelAssetPath);
    } catch (e) {
      throw ChannelLoadException('读取内置频道列表失败: $e');
    }
    return parse(raw);
  }

  /// 从 JSON 文本解析频道列表。抽成独立方法，便于直接用字符串做单元测试。
  static ChannelResponse parse(String jsonString) {
    final dynamic jsonData;
    try {
      jsonData = json.decode(jsonString);
    } on FormatException catch (e) {
      throw ChannelLoadException('频道列表 JSON 格式错误: $e');
    }

    if (jsonData is! Map<String, dynamic>) {
      throw ChannelLoadException('频道列表根节点应为对象');
    }
    return ChannelResponse.fromJson(jsonData);
  }
}

class ChannelResponse {
  final String version;
  final String url;
  final List<Channel> children;

  ChannelResponse({
    this.version = "",
    this.url = "",
    required this.children,
  });

  factory ChannelResponse.fromJson(Map<String, dynamic> json) {
    // 字段做了容错：升级用的 version/url 允许缺失，缺了只是不触发升级，
    // 不应该让整个频道列表加载失败。
    final version = json['version'] as String? ?? "";
    final url = json['url'] as String? ?? "";
    final children = ((json['children'] as List<dynamic>?) ?? const [])
        .map((childData) => Channel.fromJson(childData as Map<String, dynamic>))
        // 播放地址为空的条目没有意义，直接丢弃，避免播放器对着空地址初始化。
        .where((channel) => channel.url.isNotEmpty)
        .toList();

    return ChannelResponse(version: version, url: url, children: children);
  }
}

class Channel {
  final String name;
  final String logo;
  final String url;

  Channel({required this.name, required this.logo, required this.url});

  factory Channel.fromJson(Map<String, dynamic> json) {
    return Channel(
      name: json['name'] as String? ?? "",
      logo: json['logo'] as String? ?? "",
      url: json['url'] as String? ?? "",
    );
  }
}
