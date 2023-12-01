import 'package:fluttertoast/fluttertoast.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

class TvUtil {
  static const url = "https://tv.huandreamer.top/";

  static Future<ChannelResponse> fetchData() async {
    final response = await http.get(Uri.parse(url));

    if (response.statusCode == 200) {
      final jsonData = json.decode(response.body) as dynamic;

      final group = ChannelResponse.fromJson(jsonData);
      return group;
    } else {
      Fluttertoast.showToast(
        msg: '请求频道列表错误',
        toastLength: Toast.LENGTH_SHORT,
        gravity: ToastGravity.BOTTOM,
        timeInSecForIosWeb: 2,
      );
      return ChannelResponse(children: []);
    }
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
    final version = json['version'] as String;
    final url = json['url'] as String;
    final children = (json['children'] as List<dynamic>)
        .map((childData) => Channel.fromJson(childData))
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
    final name = json['name'] as String;
    final logo = json['logo'] as String;
    final url = json['url'] as String;

    return Channel(name: name, logo: logo, url: url);
  }
}
