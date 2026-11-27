// 🏆 The weekly tournament: one of the stalls' own things each week, the same for everyone. The lowest price on it
// this week (Monday to Sunday) leads, on the market server's board of best prices (which already ranks everyone's
// best price on each item every week). Top of it, with at least one other player, earns a prize once a week.
import 'progress.dart' show dayKey, stableHash;

const tournamentPrize = 10.0;

/// Monday of this week, as a day key (the same week the market server's board uses).
String weekStartKey(DateTime now) {
  final d = DateTime(now.year, now.month, now.day);
  return dayKey(d.subtract(Duration(days: d.weekday - DateTime.monday)));
}

/// This week's tournament item: one of the stalls' own things (not a rental), the same for everyone.
({String stall, Map item})? tournamentItem(DateTime now, Map content) {
  final all = [
    for (final s in (content['stalls'] as List).cast<Map>())
      for (final i in (s['items'] as List).cast<Map>())
        if ('${s['id']}/${i['id']}' != 'tan/bicycle') (stall: '${s['id']}', item: i),
  ];
  if (all.isEmpty) return null;
  return all[stableHash('hawker-haggle-tournament-${weekStartKey(now)}') % all.length];
}
