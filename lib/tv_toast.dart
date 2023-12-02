

import 'package:fluttertoast/fluttertoast.dart';

class TvToast {
  static void show(String message) {
    Fluttertoast.showToast(
      msg: '发现新版本正在升级',
      toastLength: Toast.LENGTH_SHORT,
      gravity: ToastGravity.BOTTOM,
      timeInSecForIosWeb: 2,
    );
  }
}