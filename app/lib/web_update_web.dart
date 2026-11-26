import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:web/web.dart' as web;

/// True when the published version.json has a higher build number than this page's.
Future<bool> newerWebVersion(int mine) async {
  if (mine <= 0) return false;
  try {
    final url = Uri.base
        .resolve('version.json')
        .replace(queryParameters: {'t': '${DateTime.now().millisecondsSinceEpoch}'});
    final r = await http.get(url).timeout(const Duration(seconds: 10));
    if (r.statusCode != 200) return false;
    final n = int.tryParse('${(jsonDecode(r.body) as Map)['build_number']}') ?? 0;
    return n > mine;
  } catch (_) {
    return false;
  }
}

void reloadPage() => web.window.location.reload();

/// This page's address (a friend's challenge link opens the game with it).
String pageAddress() => web.window.location.href;

/// Takes the challenge out of the address once it's used, so a reload doesn't start it again.
void forgetPageQuery() {
  try {
    web.window.history.replaceState(null, '', web.window.location.pathname);
  } catch (_) {}
}
