import 'package:flutter/material.dart';
import 'package:untitled/tv_util.dart';
import 'package:chewie/chewie.dart';
import 'package:video_player/video_player.dart';


void main() {
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

  @override
  void initState() {
    super.initState();

    initData();

  }

  initData() async {
    var data = await TvUtil.fetchData();
    setState(() {
      groups = data;
      currentChannel = groups[0].children[0];

      if (currentChannel.url != "") {
        changeChannel();
        hasInit = true;
      }
    });
  }

  changeChannel() {
    _videoPlayerController =
        VideoPlayerController.networkUrl(Uri.parse(currentChannel.url));
    _chewieController = ChewieController(
      videoPlayerController: _videoPlayerController,
      autoPlay: true,
      looping: false,
      autoInitialize: true,
        aspectRatio: 16/9.0,
    );
  }

  @override
  Widget build(BuildContext context) {

    int? _expandedIndex;


    return Scaffold(
      appBar: AppBar(
        title: Text('抽屉示例'),
      ),
      body: Center(
        child: hasInit ? Chewie(controller: _chewieController) : Text("初始化中"),
      ),
      drawer: Drawer(
        child: ListView.builder(
          itemCount: groups.length,
          itemBuilder: (context, index) {
            final group = groups[index];
            print(group);
            return ExpansionPanelList(
              expansionCallback: (int panelIndex, bool isExpanded) {
                setState(() {
                  _expandedIndex = isExpanded ? null : panelIndex;
                });
              },
              children: [
                ExpansionPanel(
                  headerBuilder: (BuildContext context, bool isExpanded) {
                    return ListTile(
                      title: Text(group.group),
                    );
                  },
                  body: Padding(
                    padding: const EdgeInsets.only(left: 8.0),
                    child: Column(
                      children: group.children.map((child) {
                        return ListTile(
                          title: Text(child.name),
                          onTap: () {
                            setState(() {
                              currentChannel = child;
                              changeChannel();
                            });
                          },
                        );
                      }).toList(),
                    ),
                  ),
                  isExpanded: true,
                ),
              ],
            );
          },
        ),
      ),
    );
  }

}