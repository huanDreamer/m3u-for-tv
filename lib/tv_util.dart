import 'package:http/http.dart' as http;
import 'dart:convert';

class TvUtil {
  static const url = "https://tv.huandreamer.top/";

  static Future<List<ChannelGroup>> fetchData() async {
    final response = await http.get(Uri.parse(url));

    if (response.statusCode == 200) {
      final jsonData = json.decode(response.body) as List<dynamic>;

      return jsonData.map((groupData) {
        final group = ChannelGroup.fromJson(groupData);
        return group;
      }).toList();
    } else {
      throw Exception('Failed to load data');
    }
  }
}

class ChannelGroup {
  final String group;
  final List<Channel> children;

  ChannelGroup({required this.group, required this.children});

  factory ChannelGroup.fromJson(Map<String, dynamic> json) {
    final group = json['group'] as String;
    final children = (json['children'] as List<dynamic>)
        .map((childData) => Channel.fromJson(childData))
        .toList();

    return ChannelGroup(group: group, children: children);
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
