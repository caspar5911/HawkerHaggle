/// "Can you beat me?" links: a deal shared with a link that opens the same haggle for a friend, with your price to
/// beat. The link holds everything (stall, item, price, name), so no server is needed. It opens the web version (any
/// phone, nothing to install); players with the app can paste it under Friends.
library;

import 'core/game.dart' show cleanName;

/// The game's public web address (GitHub Pages).
const webHome = 'https://caspar5911.github.io/HawkerHaggle/';

typedef Challenge = ({String stall, String item, double price, String name});

String challengeLink({required String stall, required String item, required num price, required String name}) =>
    Uri.parse(webHome)
        .replace(
          queryParameters: {
            'beat': price.toDouble().toStringAsFixed(2),
            'stall': stall,
            'item': item,
            'by': cleanName(name) ?? '',
          },
        )
        .toString();

/// The challenge in a link (or in a message with a link somewhere in it), or null.
Challenge? parseChallenge(String text) {
  for (final m in RegExp(r'https?://\S+').allMatches(text)) {
    final u = Uri.tryParse(m.group(0)!);
    final q = u?.queryParameters ?? const {};
    final price = double.tryParse(q['beat'] ?? '');
    final stall = q['stall'] ?? '', item = q['item'] ?? '';
    if (price == null || !price.isFinite || price <= 0 || price > 100000) continue;
    if (!RegExp(r'^[a-z0-9_]{1,30}$').hasMatch(stall) || !RegExp(r'^[a-z0-9_]{1,30}$').hasMatch(item)) continue;
    return (stall: stall, item: item, price: (price * 100).round() / 100, name: cleanName(q['by'] ?? '') ?? 'A friend');
  }
  return null;
}
