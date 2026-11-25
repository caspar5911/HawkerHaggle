// A skilled haggle for tests that need a near-best price: goodwill first, real bargaining up from a bold offer, and
// only then a firm price at her lowest. (Rushing to a firm number no longer gets her real lowest price.)
import 'package:hawker_haggle/core/game.dart';

String _money(num x) => x == x.roundToDouble() ? '\$${x.toInt()}' : '\$${x.toStringAsFixed(2)}';

double _nice(num p) {
  final step = p < 20 ? 0.5 : 1.0;
  return (p / step).round() * step;
}

Future<Map> haggleWell(Game g, Map content, String stall, String item, {String surprise = 'none'}) async {
  final it = ((content['stalls'] as List).firstWhere((s) => s['id'] == stall)['items'] as List).firstWhere(
    (i) => i['id'] == item,
  );
  final floor = (it['floor'] as num).toDouble();
  final lo = _nice(floor * 0.85);
  var r = await g.start(stall, item, surprise);
  final id = r['id'] as String;
  for (final t in [
    'wah so nice',
    '${_money(lo)} can?',
    'I come every week',
    'so fresh, very good',
    '${_money(_nice((lo + floor) / 2))} can?',
    '${_money(floor)} can?',
    '${_money(floor)} can?',
  ]) {
    r = await g.move(id, text: t);
    if (r['done'] == true || r['pending'] != null) break;
  }
  if (r['done'] != true && r['pending'] == null) r = await g.move(id, text: '${_money(r['ask'] as num)} ok I take');
  return r['pending'] != null ? g.move(id, move: 'confirm') : r;
}
