/// A month of things to do: a daily challenge, weekly quests, a rank built from XP (mostly from once-a-day
/// sources, so it takes weeks, not one long evening), and a 30-day "Market Month" counted in days played.
/// Every check reads the per-haggle summaries the game records, so each one is testable on its own.
library;

import 'dart:math' as math;

import 'progress.dart';

/// Ranks: XP needed for each, and its title.
const ranks = <(int, String)>[
  (0, 'Rookie Shopper'),
  (100, 'Market Newbie'),
  (250, 'Bargain Spotter'),
  (450, 'Wet Market Regular'),
  (700, 'Haggle Apprentice'),
  (1000, 'Sharp Shopper'),
  (1350, 'Pasar Malam Pro'),
  (1750, 'Discount Detective'),
  (2200, 'Kiasu Champion'),
  (2700, 'Haggle Master'),
  (3250, "Auntie's Favourite"),
  (3850, 'Market Legend'),
  (4500, 'Bargain Sifu'),
  (5200, 'Hawker Hero'),
  (6000, 'Haggle Grandmaster'),
];

/// XP for each source.
const xpDailyChallenge = 60, xpList = 40, xpListUnder = 20, xpQuest = 60, xpAllQuests = 100, xpDayPlayed = 20;
const xpGuessSpotOn = 4, xpGuessClose = 2; // guessing the fair price before a haggle (inside the haggle cap)
const xpHaggleCapPerDay = 60; // XP from haggles themselves is capped per day, so grinding can't rush the month

/// Market Month milestones: days played -> what it gives.
const milestones = <(int, String, String)>[
  (2, '🏺', "Uncle Wong's antique stall opens"),
  (3, '🌱', 'Sticker: Three market days'),
  (5, '🌶️', "Madam Kumar's spice shop opens"),
  (9, '🐔', "Ah Ma Tan's kampung shop opens"),
  (21, '🏅', 'A golden name badge'),
  (30, '👑', 'Sticker and title: Hawker of the Month'),
];

/// One kind of daily challenge: a title, how to do it, and the check on a day's haggle records.
class Daily {
  const Daily(this.id, this.title, this.how, this.check, {this.surprise = '', this.stall = ''});
  final String id, title, how;
  final bool Function(List<Map> todays, Map? last) check;
  final String surprise; // the Play button starts this surprise, so it can always be done today
  final String stall; // the Play button opens this stall
}

bool _deal(Map r) => r['result'] == 'deal';
num _n(Object? v) => (v ?? 0) as num;

int _hash(String s) {
  var h = 0x811c9dc5;
  for (final c in s.codeUnits) {
    h = ((h ^ c) * 0x01000193) & 0x7fffffff;
  }
  return h;
}

/// Monday of the week [d] is in (weeks run Monday to Sunday).
DateTime weekStart(DateTime d) {
  final day = DateTime(d.year, d.month, d.day);
  return day.subtract(Duration(days: day.weekday - 1));
}

class Challenges {
  Challenges(this.progress);
  final Progress progress;

  Map<String, Object?> get p => progress.p;
  DateTime get now => progress.now();
  String get today => dayKey(now);
  Map<String, Map> get _stalls => {for (final s in progress.content['stalls'] as List) (s as Map)['id'] as String: s};
  List<Map> get _records => [for (final h in (p['haggles'] as List? ?? const [])) h as Map];

  /// An item's fair price (per piece), for the guess.
  double? _fairPrice(Map r) {
    for (final i in (_stalls['${r['stall']}']?['items'] as List? ?? const [])) {
      if ((i as Map)['id'] == r['item'] && i['fair'] != null) return (i['fair'] as num).toDouble();
    }
    return null;
  }

  static String _price(num v) => v == v.roundToDouble() ? '\$${v.toInt()}' : '\$${v.toStringAsFixed(2)}';
  Map<String, Object?> _map(String k) => (p[k] ??= <String, Object?>{}) as Map<String, Object?>;

  String _name(String stall) => '${_stalls[stall]?['name'] ?? stall}';

  /// The item a challenge names: one that a day's pocket money can cover (a first price up to \$30), so today's
  /// challenge is never out of reach.
  Map _item(String stall, int k) {
    final all = (_stalls[stall]!['items'] as List).cast<Map>();
    final items = all.where((i) => (i['ask'] as num) <= 30).toList();
    final pool = items.isEmpty ? all : items;
    return pool[k % pool.length];
  }

  // ---------------------------------------------------------------- daily challenge
  /// The pool, with today's stall and item filled in. Base stalls only, and every one works without the AI.
  List<Daily> pool(int h) {
    final st = baseStalls[h % 4];
    final it = _item(st, h ~/ 7);
    final who = _name(st);
    bool atStall(Map r) => r['stall'] == st;
    return [
      Daily(
        'deal_at',
        'Buy from $who',
        'Close any deal at $who\'s stall.',
        (t, l) => t.any((r) => _deal(r) && atStall(r)),
        stall: st,
      ),
      Daily(
        'stars2_item',
        'Two stars on ${it['name']}',
        'Get 2 or more stars on the ${it['name']}.',
        (t, l) => t.any((r) => _deal(r) && r['item'] == it['id'] && _n(r['stars']) >= 2),
        stall: st,
      ),
      Daily(
        'three_stars',
        'A three-star bargain',
        'Get 3 stars on any item.',
        (t, l) => t.any((r) => _deal(r) && _n(r['stars']) >= 3),
      ),
      Daily(
        'off30',
        '30% off',
        'Buy anything for at least 30% off its first price.',
        (t, l) => t.any((r) => _deal(r) && _n(r['saved']) >= 0.3),
      ),
      Daily(
        'quick',
        'Quick deal',
        'Close a deal in 4 moves or fewer.',
        (t, l) => t.any((r) => _deal(r) && _n(r['moves']) <= 4),
      ),
      Daily(
        'patient',
        'Keep her happy',
        'Close a deal while her patience is still above half.',
        (t, l) => t.any((r) => _deal(r) && _n(r['patience']) > 50),
      ),
      Daily(
        'typed_only',
        'In your own words',
        'Close a deal typing every message yourself (no suggestions).',
        (t, l) => t.any((r) => _deal(r) && _n(r['typed']) > 0 && _n(r['tapped']) == 0),
      ),
      Daily('buy_two', 'Buy two', 'Buy two of something.', (t, l) => t.any((r) => _deal(r) && _n(r['qty']) > 1)),
      Daily(
        'final_final',
        'Final-final',
        'Walk away, get called back, then buy.',
        (t, l) => t.any((r) => _deal(r) && r['called_back'] == true),
        stall: 'raj',
      ),
      Daily(
        'beat_rose',
        'Faster than Auntie Rose',
        'Buy the last one before Auntie Rose does.',
        (t, l) => t.any((r) => _deal(r) && r['event'] == 'rival'),
        surprise: 'rival',
        stall: st,
      ),
      Daily(
        'rain_deal',
        'Rainy-day bargain',
        'Close a deal on a rainy day.',
        (t, l) => t.any((r) => _deal(r) && r['event'] == 'rain'),
        surprise: 'rain',
        stall: st,
      ),
      Daily(
        'festival_deal',
        'Festival haggler',
        'Close a deal on festival day, below the festival price.',
        (t, l) => t.any((r) => _deal(r) && r['event'] == 'festival' && _n(r['saved']) > 0),
        surprise: 'festival',
        stall: st,
      ),
      Daily(
        'closing_deal',
        'Last-minute deal',
        'Close a deal at closing time.',
        (t, l) => t.any((r) => _deal(r) && r['event'] == 'closing'),
        surprise: 'closing',
        stall: st,
      ),
      Daily(
        'sweet_talk',
        'Sweet talker',
        'Pay a compliment, then close the deal.',
        (t, l) => t.any((r) => _deal(r) && (r['tactics'] as List? ?? const []).contains('compliment')),
        stall: st,
      ),
      Daily(
        'regular',
        'Old friend',
        "Tell them you're a regular, then close the deal.",
        (t, l) => t.any((r) => _deal(r) && (r['tactics'] as List? ?? const []).contains('regular')),
        stall: st,
      ),
      Daily(
        'competitor',
        'Next stall cheaper',
        'Say the next stall is cheaper, and still close a deal.',
        (t, l) => t.any((r) => _deal(r) && (r['tactics'] as List? ?? const []).contains('competitor')),
        stall: st,
      ),
      Daily(
        'budget',
        'Know your budget',
        'Tell them how much you have, then close a deal.',
        (t, l) => t.any((r) => _deal(r) && (r['tactics'] as List? ?? const []).contains('budget')),
        stall: st,
      ),
      Daily(
        'two_stalls',
        'Market hopper',
        'Close deals at two different stalls today.',
        (t, l) => t.where(_deal).map((r) => r['stall']).toSet().length >= 2,
      ),
      Daily('three_deals', 'Busy shopper', 'Close three deals today.', (t, l) => t.where(_deal).length >= 3),
      Daily(
        'polite',
        'Polite all the way',
        'Close two deals today without being rude once.',
        (t, l) => t.where((r) => _deal(r) && r['rude'] != true).length >= 2 && !t.any((r) => r['rude'] == true),
      ),
      Daily(
        'pity',
        'Sad story',
        'Tell a sad story, then close the deal.',
        (t, l) => t.any((r) => _deal(r) && (r['tactics'] as List? ?? const []).contains('pity')),
        stall: st,
      ),
      Daily(
        'under_fair',
        'Fair price',
        'Buy the ${it['name']} at a good price (2 stars or more).',
        (t, l) => t.any((r) => _deal(r) && r['item'] == it['id'] && _n(r['stars']) >= 2),
        stall: st,
      ),
    ];
  }

  /// Today's challenge: the same for everyone today.
  Daily daily([DateTime? on]) {
    final day = dayKey(on ?? now);
    final h = _hash('daily-$day');
    final all = pool(h);
    return all[h % all.length];
  }

  bool dailyDone() => _map('done_daily')[today] == true;

  // ---------------------------------------------------------------- weekly quests
  /// This week's four quests (the same for everyone this week). Each: id, title, target, and how far you are.
  List<Map<String, Object?>> quests() {
    final ws = weekStart(now);
    final wk = dayKey(ws);
    final h = _hash('week-$wk');
    final st = baseStalls[h % 4];
    final inWeek = _records.where((r) {
      final d = DateTime.tryParse('${r['day'] ?? r['at'] ?? ''}');
      return d != null && !d.isBefore(ws) && d.isBefore(ws.add(const Duration(days: 7)));
    }).toList();
    final listDays = ((_map('list_days')).keys.where((d) {
      final x = DateTime.parse(d);
      return !x.isBefore(ws) && x.isBefore(ws.add(const Duration(days: 7)));
    })).length;
    final dailies = ((_map('done_daily')).keys.where((d) {
      final x = DateTime.parse(d);
      return !x.isBefore(ws) && x.isBefore(ws.add(const Duration(days: 7)));
    })).length;
    final candidates = <(String, String, int, int)>[
      ('deals', 'Close 6 deals', 6, inWeek.where(_deal).length),
      ('stall', 'Close 3 deals at ${_name(st)}\'s stall', 3, inWeek.where((r) => _deal(r) && r['stall'] == st).length),
      ('list', "Finish Mum's list on 3 days", 3, listDays),
      ('stars', 'Earn 10 stars', 10, inWeek.where(_deal).fold<int>(0, (a, r) => a + _n(r['stars']).toInt())),
      ('dailies', 'Finish 4 daily challenges', 4, dailies),
      (
        'surprises',
        'Close 2 deals during market surprises',
        2,
        inWeek.where((r) => _deal(r) && '${r['event'] ?? ''}'.isNotEmpty).length,
      ),
      ('items', 'Haggle for 5 different items', 5, inWeek.map((r) => '${r['stall']}/${r['item']}').toSet().length),
      (
        'typed',
        'Close 3 deals typing every message',
        3,
        inWeek.where((r) => _deal(r) && _n(r['typed']) > 0 && _n(r['tapped']) == 0).length,
      ),
    ];
    // four of them, picked by the week
    final picked = <(String, String, int, int)>[];
    var k = h;
    while (picked.length < 4) {
      final c = candidates[k % candidates.length];
      if (!picked.contains(c)) picked.add(c);
      k = k ~/ 3 + 7;
    }
    return [
      for (final (id, title, target, have) in picked)
        {'id': id, 'title': title, 'target': target, 'have': math.min(have, target), 'done': have >= target},
    ];
  }

  String get weekKey => dayKey(weekStart(now));

  // ---------------------------------------------------------------- rank and XP
  int get xp => _n(p['xp']).toInt();

  void _addXp(int n) => p['xp'] = xp + n;

  Map<String, Object?> rank() {
    var i = 0;
    while (i + 1 < ranks.length && xp >= ranks[i + 1].$1) {
      i++;
    }
    final next = i + 1 < ranks.length ? ranks[i + 1].$1 : null;
    return {'level': i + 1, 'title': ranks[i].$2, 'xp': xp, 'from': ranks[i].$1, 'next': next, 'max': next == null};
  }

  // ---------------------------------------------------------------- Market Month
  /// Days you've played (finished at least one haggle), not in a row: missing a day never resets it.
  int daysPlayed() => _map('days').length;

  List<Map<String, Object?>> month() => [
    for (final (day, emoji, what) in milestones)
      {'day': day, 'emoji': emoji, 'what': what, 'reached': daysPlayed() >= day},
  ];

  // ---------------------------------------------------------------- after each haggle
  /// Called once when a haggle ends (after Progress.finish). Returns what was earned, to show on the result card.
  List<String> onFinish(Map record, {required bool listDone, required bool listUnder, required Set<String> stickers}) {
    final notes = <String>[];
    final levelBefore = rank()['level'] as int;
    final day = today;
    // a day played
    final days = _map('days');
    if (!days.containsKey(day)) {
      days[day] = true;
      _addXp(xpDayPlayed);
      for (final (d, emoji, what) in milestones) {
        if (daysPlayed() == d) notes.add('$emoji Day $d of your Market Month: $what!');
      }
      if (daysPlayed() >= 3) progress.earn('days3', stickers);
      if (daysPlayed() >= 30) progress.earn('month', stickers);
    }
    // XP from the haggle itself, capped per day
    final xpDay = _map('xp_day');
    if (xpDay['day'] != day) {
      xpDay
        ..clear()
        ..['day'] = day
        ..['haggles'] = 0;
    }
    var gain = _deal(record) ? 5 + 3 * _n(record['stars']).toInt() : 2;
    // the fair-price guess (inside the same daily cap, so it can't rush the month)
    final fair = _fairPrice(record);
    if (record['guess'] != null && fair != null) {
      final off = (_n(record['guess']) - fair).abs() / fair;
      final bonus = off <= 0.05 ? xpGuessSpotOn : (off <= 0.15 ? xpGuessClose : 0);
      gain += bonus;
      notes.add(
        '🤔 You guessed ${_price(_n(record['guess']))}; the fair price is ${_price(fair)}. '
        '${off <= 0.05 ? 'Spot on!' : (off <= 0.15 ? 'Close!' : (_n(record['guess']) > fair ? 'A bit high.' : 'A bit low.'))}'
        '${bonus > 0 ? ' +$bonus XP' : ''}',
      );
      final sharp = _records.where((r) {
        final f = _fairPrice(r);
        return r['guess'] != null && f != null && (_n(r['guess']) - f).abs() / f <= 0.10;
      }).length;
      if (sharp >= 5) progress.earn('sharp_eye', stickers);
    }
    final room = xpHaggleCapPerDay * (progress.owns('school') ? 2 : 1) - _n(xpDay['haggles']).toInt(); // 📚
    final got = math.max(0, math.min(gain, room));
    xpDay['haggles'] = _n(xpDay['haggles']).toInt() + got;
    _addXp(got);
    // Mum's list
    if (listDone && _map('list_days')[day] == null) {
      _map('list_days')[day] = true;
      _addXp(xpList + (listUnder ? xpListUnder : 0));
    }
    // the daily challenge
    final todays = _records.where((r) => r['day'] == day).toList();
    if (!dailyDone() && daily().check(todays, record)) {
      _map('done_daily')[day] = true;
      final dxp = progress.owns('coin') ? xpDailyChallenge * 3 ~/ 2 : xpDailyChallenge; // 🪙 the lucky coin
      _addXp(dxp);
      progress.reward(moneyDaily);
      notes.add('🎯 Daily challenge done: ${daily().title}! +$dxp XP, +${_price(moneyDaily)}');
      final count = _map('done_daily').length;
      if (count >= 7) progress.earn('dailies7', stickers);
    }
    // weekly quests
    final qDone = _map('quests_done');
    final wk = weekKey;
    final doneThisWeek = ((qDone[wk] ??= <String, Object?>{}) as Map);
    final qs = quests();
    for (final q in qs) {
      if (q['done'] == true && doneThisWeek[q['id']] != true) {
        doneThisWeek[q['id'] as String] = true;
        _addXp(xpQuest);
        progress.reward(moneyQuest);
        notes.add('📋 Weekly quest done: ${q['title']}! +$xpQuest XP, +${_price(moneyQuest)}');
      }
    }
    if (qs.every((q) => q['done'] == true) && doneThisWeek['all'] != true) {
      doneThisWeek['all'] = true;
      _addXp(xpAllQuests);
      progress.reward(moneyAllQuests);
      progress.earn('week_done', stickers);
      notes.add('🏆 All of this week\'s quests done! +$xpAllQuests XP, +${_price(moneyAllQuests)}');
    }
    // 🎖️ a new rank: \$5 times the new level (for each level reached at once)
    final levelAfter = rank()['level'] as int;
    if (levelAfter > levelBefore) {
      var money = 0.0;
      for (var l = levelBefore + 1; l <= levelAfter; l++) {
        money += moneyPerRank * l;
      }
      progress.reward(money);
      notes.add('🎖️ New rank: ${rank()['title']}! +${_price(money)}');
    }
    return notes;
  }

  /// Everything for the Challenges screen.
  Map<String, Object?> summary() {
    final d = daily();
    return {
      'rank': rank(),
      'daily': {
        'id': d.id,
        'title': d.title,
        'how': d.how,
        'done': dailyDone(),
        'surprise': d.surprise,
        'stall': d.stall,
      },
      'quests': quests(),
      'week_ends': dayKey(weekStart(now).add(const Duration(days: 6))),
      'days_played': daysPlayed(),
      'month': month(),
    };
  }
}
