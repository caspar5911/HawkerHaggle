/// The game around the haggles: friendship with each stallholder, Mum's daily shopping list and streak, stickers,
/// stall unlocks, tips and backstories. Everything lives in the player's profile on the phone.
library;

import 'dart:math' as math;

import 'challenges.dart';

/// Base stalls: open from the start, and the only ones the daily list uses (so it's the same list for everyone).
const baseStalls = ['mei', 'lim', 'raj', 'siti'];

/// Friendship levels: points needed for 1, 2 and 3 hearts.
const heartAt = [10, 30, 60];

/// Every sticker, in book order: id, emoji, title, how to get it.
const stickerDefs = <(String, String, String, String)>[
  ('first_deal', '🤝', 'First deal', 'Close your first deal'),
  ('three_stars', '⭐', 'Three-star bargain', 'Get 3 stars on any item'),
  ('all_stalls', '🏮', 'Market regular', 'Haggle at all four first stalls'),
  ('half_off', '✂️', 'Half price!', 'Get something for half its first price'),
  ('final_final', '🔁', 'Final-final', 'Walk away, get called back, then buy'),
  ('rival_beaten', '🏃', 'Faster than Auntie Rose', 'Beat the rival auntie to the last one'),
  ('lost_rival', '😱', 'Too slow!', 'Lose the last one to Auntie Rose'),
  ('rain_deal', '🌧️', 'Rainy-day bargain', 'Close a deal on a rainy day'),
  ('closing_deal', '⏰', 'Last-minute deal', 'Close a deal at closing time'),
  ('festival_deal', '🎉', 'Festival shopper', 'Close a deal on a festival day'),
  ('list_done', '📝', "Mum's list done", "Buy everything on Mum's list"),
  ('list_under', '💰', 'Under budget!', "Finish Mum's list within budget"),
  ('streak3', '🔥', 'Three-day streak', "Finish Mum's list 3 days in a row"),
  ('friend', '💛', 'New friend', 'Reach 2 hearts with a stallholder'),
  ('best_friend', '💖', 'Best friends', 'Reach 3 hearts with a stallholder'),
  ('lim_smile', '🐟', 'Made Uncle Lim smile', 'Reach 2 hearts with Uncle Lim'),
  ('new_stall', '🔓', 'New stall unlocked', 'Unlock a new stall with your stars'),
  ('hard_deal', '🥋', 'Hard-mode haggler', 'Close a deal in hard mode'),
  ('days3', '🌱', 'Three market days', 'Play on 3 different days'),
  ('dailies7', '🎯', 'Challenge seeker', 'Finish 7 daily challenges'),
  ('week_done', '🏆', 'Quest week', "Finish all of a week's quests"),
  ('month', '👑', 'Hawker of the Month', 'Play on 30 different days'),
];

String dayKey(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// A stable number from text (FNV-1a), so the daily list is the same on every phone.
int _hash(String s) {
  var h = 0x811c9dc5;
  for (final c in s.codeUnits) {
    h = ((h ^ c) * 0x01000193) & 0x7fffffff;
  }
  return h;
}

String _money(num v) => v == v.roundToDouble() ? '\$${v.toInt()}' : '\$${v.toStringAsFixed(2)}';

class Progress {
  Progress(this.p, this.content, this.now);
  final Map<String, Object?> p; // the profile (saved by the game)
  final Map content;
  final DateTime Function() now;

  Map<String, Map> get _stalls => {for (final s in content['stalls'] as List) (s as Map)['id'] as String: s};
  List<Map> get _haggles => [for (final h in (p['haggles'] as List? ?? const [])) h as Map];
  Map<String, Object?> _map(String k) => (p[k] ??= <String, Object?>{}) as Map<String, Object?>;

  /// Fill in anything an older profile (test 12 and before) doesn't have, and give credit for past haggles.
  void migrate() {
    p['haggles'] ??= <Object>[];
    p['reports'] ??= <Object>[];
    p['hard'] ??= false;
    if (p['friends'] == null) {
      p['friends'] = <String, Object?>{};
      for (final h in _haggles) {
        _addPoints('${h['stall']}', h['result'] == 'deal' ? 8 : 2, daily: false);
        _friend('${h['stall']}')['visits'] = ((_friend('${h['stall']}')['visits'] ?? 0) as num).toInt() + 1;
        if (h['result'] == 'deal') _friend('${h['stall']}')['last_item'] = h['item'];
      }
    }
    if (p['stickers'] == null) {
      p['stickers'] = <String, Object?>{};
      for (final h in _haggles) {
        _stickersForHaggle(h, const {});
      }
      _friendStickers();
    }
    _map('daily');
    _map('streak');
    if (p['xp'] == null) {
      // credit for haggles from before the challenges existed: days played, and capped XP per day
      final days = _map('days');
      final perDay = <String, int>{};
      for (final h in _haggles) {
        final d = '${h['at'] ?? ''}'.length >= 10 ? '${h['at']}'.substring(0, 10) : null;
        if (d == null) continue;
        days[d] = true;
        final gain = h['result'] == 'deal' ? 5 + 3 * ((h['stars'] ?? 0) as num).toInt() : 2;
        perDay[d] = math.min(xpHaggleCapPerDay, (perDay[d] ?? 0) + gain);
      }
      p['xp'] = days.length * xpDayPlayed + perDay.values.fold<int>(0, (a, b) => a + b);
    }
  }

  // ---------------------------------------------------------------- friendship
  Map<String, Object?> _friend(String stall) =>
      ((_map('friends'))[stall] ??= <String, Object?>{'points': 0, 'visits': 0}) as Map<String, Object?>;

  int points(String stall) => ((_friend(stall)['points'] ?? 0) as num).toInt();
  int hearts(String stall) => heartAt.where((t) => points(stall) >= t).length;

  /// Friendship goes up with visits and deals (at most 15 a day per stall, so it can't be farmed) and down with
  /// rudeness.
  void _addPoints(String stall, int n, {bool daily = true}) {
    final f = _friend(stall);
    if (n > 0 && daily) {
      final today = dayKey(now());
      if (f['day'] != today) {
        f['day'] = today;
        f['gained'] = 0;
      }
      final room = 15 - ((f['gained'] ?? 0) as num).toInt();
      n = math.max(0, math.min(n, room));
      f['gained'] = ((f['gained'] ?? 0) as num).toInt() + n;
    }
    f['points'] = math.max(0, math.min(100, points(stall) + n));
  }

  /// A short, number-free note for the AI, so a friend is greeted like a friend.
  String memoryNote(String stall, String playerName) {
    final lvl = hearts(stall);
    if (lvl == 0) return '';
    final f = _friend(stall);
    final visits = ((f['visits'] ?? 0) as num).toInt();
    final lastItem = (_stalls[stall]?['items'] as List? ?? const [])
        .cast<Map>()
        .where((i) => i['id'] == f['last_item'])
        .map((i) => '${i['name']}')
        .firstOrNull;
    final name = playerName.replaceAll(RegExp(r'\s*\d+$'), '');
    return [
      'You know this customer${lvl >= 2 ? ', $name' : ''}: they have come to your stall ${visits > 5 ? 'many times' : 'a few times'}.',
      if (lastItem != null) 'Last time they bought your $lastItem; you may ask how it was.',
      if (lvl >= 3) 'They are one of your favourite customers: be extra warm.',
      if (((f['rude'] ?? 0) as num) > 0 && lvl < 2) 'They were rude to you once; you remember.',
    ].join(' ');
  }

  // ---------------------------------------------------------------- unlocks
  /// Stars that count for unlocks: the best result on each item (so replaying one item can't farm them).
  int bestStars() {
    final best = <String, int>{};
    for (final h in _haggles) {
      final k = '${h['stall']}/${h['item']}';
      best[k] = math.max(best[k] ?? 0, ((h['stars'] ?? 0) as num).toInt());
    }
    return best.values.fold(0, (a, b) => a + b);
  }

  int unlockAt(String stall) => ((_stalls[stall]?['unlock_stars'] ?? 0) as num).toInt();
  int unlockDays(String stall) => ((_stalls[stall]?['unlock_days'] ?? 0) as num).toInt();
  int daysPlayed() => _map('days').length;
  bool unlocked(String stall) => bestStars() >= unlockAt(stall) && daysPlayed() >= unlockDays(stall);

  // ---------------------------------------------------------------- Mum's daily list
  /// Today's list: two items from two different first stalls, the same for everyone today. The budget is based on
  /// the fair prices (never the secret lowest ones).
  Map<String, Object?> today() {
    final day = dayKey(now());
    final h = _hash('hawker-haggle-$day');
    final s1 = baseStalls[h % 4];
    final s2 = baseStalls[(h % 4 + 1 + (h ~/ 4) % 3) % 4]; // always a different stall
    final picks = <Map>[];
    for (final (i, st) in [s1, s2].indexed) {
      final items = _stalls[st]!['items'] as List;
      final it = items[(h >> (8 + i * 3)) % items.length] as Map;
      picks.add({'stall': st, 'item': it['id'], 'name': it['name'], 'emoji': it['emoji'], 'fair': it['fair']});
    }
    final budget = (picks.fold<double>(0, (a, i) => a + (i['fair'] as num)) * 1.05).ceilToDouble();
    final d = _map('daily');
    if (d['date'] != day) {
      d
        ..clear()
        ..['date'] = day
        ..['bought'] = <String, Object?>{};
    }
    final bought = (d['bought'] as Map).cast<String, Object?>();
    final spent = bought.values.fold<double>(0, (a, v) => a + (v as num));
    final done = picks.every((i) => bought.containsKey('${i['stall']}/${i['item']}'));
    final tips = (_stalls[picks.first['stall']]!['tips'] as List? ?? const []).cast<String>();
    return {
      'date': day,
      'items': [
        for (final i in picks)
          {
            ...i,
            'done': bought.containsKey('${i['stall']}/${i['item']}'),
            'paid': bought['${i['stall']}/${i['item']}'],
          },
      ],
      'budget': budget,
      'spent': spent,
      'complete': done,
      'under': done && spent <= budget,
      'streak': streak(),
      'tip': tips.isEmpty ? '' : tips[h % tips.length],
    };
  }

  /// Current streak of days with Mum's list done (shows 0 once a day is missed).
  int streak() {
    final s = _map('streak');
    final last = s['last'] as String?;
    if (last == null) return 0;
    final today = DateTime.parse(dayKey(now()));
    final gap = today.difference(DateTime.parse(last)).inDays;
    return gap <= 1 ? ((s['count'] ?? 0) as num).toInt() : 0;
  }

  /// A deal on a list item: record it; when the list is complete, update the streak and give Mum's verdict.
  String? _onListDeal(String stall, String item, double deal, int qty, Set<String> newStickers) {
    final t = today();
    final key = '$stall/$item';
    final onList = (t['items'] as List).any((i) => '${(i as Map)['stall']}/${i['item']}' == key);
    final d = _map('daily');
    final bought = (d['bought'] as Map);
    if (!onList) return null;
    // Mum wants one of each: count the price per piece, and keep your best (lowest) price today.
    final before = bought[key] as num?;
    if (before != null && deal >= before) return null;
    final wasComplete = today()['complete'] == true;
    bought[key] = deal;
    final after = today();
    if (after['complete'] != true) {
      return before != null
          ? 'Mum: Better price this time, ${_money(deal)}! I take this one.'
          : "Mum: Good, one done! Now the other one ah. Budget ${_money(after['budget'] as num)} total.";
    }
    if (wasComplete) {
      // a better deal after the list was already done: update the verdict (and the sticker if now under budget)
      final spent = after['spent'] as double, budget = after['budget'] as double;
      if (spent <= budget) _earn('list_under', newStickers);
      return spent <= budget
          ? 'Mum: Wah, better deal! Now ${_money(spent)} total, under budget 🥰'
          : 'Mum: Better price, ${_money(spent)} total now. Still ${_money(spent - budget)} over budget ah.';
    }
    final spent = after['spent'] as double, budget = after['budget'] as double;
    final s = _map('streak');
    final todayKey = dayKey(now());
    if (s['last'] != todayKey) {
      final yesterday = dayKey(DateTime.parse(todayKey).subtract(const Duration(days: 1)));
      s['count'] = s['last'] == yesterday ? ((s['count'] ?? 0) as num).toInt() + 1 : 1;
      s['last'] = todayKey;
    }
    _earn('list_done', newStickers);
    if (spent <= budget) _earn('list_under', newStickers);
    if (streak() >= 3) _earn('streak3', newStickers);
    return spent <= budget
        ? 'Mum: Wah, so clever! ${_money(spent)}, under budget. Mum very proud of you 🥰'
        : 'Mum: Aiyo, ${_money(spent - budget)} over budget! Next time bargain harder ah 😤';
  }

  // ---------------------------------------------------------------- stickers
  Map<String, Object?> get _stickers => _map('stickers');

  void earn(String id, Set<String> fresh) => _earn(id, fresh);

  void _earn(String id, Set<String> fresh) {
    if (_stickers.containsKey(id)) return;
    _stickers[id] = dayKey(now());
    fresh.add(id);
  }

  void _stickersForHaggle(Map h, Map flags, [Set<String>? fresh]) {
    final out = fresh ?? <String>{};
    final deal = h['result'] == 'deal';
    if (deal) _earn('first_deal', out);
    if (deal && ((h['stars'] ?? 0) as num) >= 3) _earn('three_stars', out);
    if (deal && ((h['saved'] ?? 0) as num) >= 0.5) _earn('half_off', out);
    if (deal && flags['called_back'] == true) _earn('final_final', out);
    final ev = '${h['event'] ?? ''}';
    if (deal && ev == 'rival') _earn('rival_beaten', out);
    if (h['result'] == 'lost') _earn('lost_rival', out);
    if (deal && ev == 'rain') _earn('rain_deal', out);
    if (deal && ev == 'closing') _earn('closing_deal', out);
    if (deal && ev == 'festival') _earn('festival_deal', out);
    if (deal && flags['hard'] == true) _earn('hard_deal', out);
    final visited = {for (final x in _haggles) x['stall']};
    if (baseStalls.every(visited.contains)) _earn('all_stalls', out);
  }

  void _friendStickers([Set<String>? fresh]) {
    final out = fresh ?? <String>{};
    for (final st in _stalls.keys) {
      if (hearts(st) >= 2) _earn('friend', out);
      if (hearts(st) >= 3) _earn('best_friend', out);
    }
    if (hearts('lim') >= 2) _earn('lim_smile', out);
  }

  List<Map<String, Object?>> stickers() => [
    for (final (id, emoji, title, how) in stickerDefs)
      {'id': id, 'emoji': emoji, 'title': title, 'how': how, 'earned': _stickers[id]},
  ];

  // ---------------------------------------------------------------- after each haggle
  /// Called once when a haggle ends. Returns new stickers, Mum's note (if it was on her list) and new unlocks.
  ({List<String> stickers, String? mum, List<String> unlocked, List<String> notes}) finish({
    required Map record,
    required int qty,
    required Map flags,
    List<Map> chat = const [],
  }) {
    _keepChat(record, qty, chat);
    final stall = '${record['stall']}';
    final fresh = <String>{};
    final lockedBefore = {
      for (final s in _stalls.keys)
        if (!unlocked(s)) s,
    };
    (p['haggles'] as List).add(record);
    final list = p['haggles'] as List;
    if (list.length > 500) list.removeRange(0, list.length - 500);
    final f = _friend(stall);
    f['visits'] = ((f['visits'] ?? 0) as num).toInt() + 1;
    final deal = record['result'] == 'deal';
    if (deal) f['last_item'] = record['item'];
    _addPoints(stall, (deal ? 8 : 2) + math.min(3, ((flags['nice'] ?? 0) as num).toInt()));
    _stickersForHaggle(record, flags, fresh);
    _friendStickers(fresh);
    String? mum;
    if (deal && record['deal'] != null) {
      mum = _onListDeal(stall, '${record['item']}', (record['deal'] as num).toDouble(), qty, fresh);
    }
    final t = today();
    final notes = Challenges(this)
        .onFinish(record, listDone: t['complete'] == true, listUnder: t['under'] == true, stickers: fresh);
    final newly = [
      for (final s in lockedBefore)
        if (unlocked(s)) s,
    ];
    if (newly.isNotEmpty) _earn('new_stall', fresh);
    return (stickers: fresh.toList(), mum: mum, unlocked: newly, notes: notes);
  }

  // ---------------------------------------------------------------- past haggles (chat history)
  static const historyKept = 30;

  void _keepChat(Map record, int qty, List<Map> chat) {
    if (chat.isEmpty) return;
    final list = (p['history'] ??= <Object>[]) as List;
    list.add({
      'id': '${record['at']}-${record['stall']}-${record['item']}',
      'at': record['at'],
      'stall': record['stall'],
      'item': record['item'],
      'result': record['result'],
      'deal': record['deal'],
      'stars': record['stars'],
      'saved': record['saved'],
      'event': record['event'],
      'qty': qty,
      'chat': [
        for (final m in chat.length > 60 ? chat.sublist(chat.length - 60) : chat)
          {'who': m['who'], 'text': m['text'], if (m['ai'] == true) 'ai': true},
      ],
    });
    if (list.length > historyKept) list.removeRange(0, list.length - historyKept);
  }

  /// Past haggles, newest first (without the chat, for the list).
  List<Map<String, Object?>> history() {
    final items = {
      for (final s in content['stalls'] as List)
        for (final i in (s as Map)['items'] as List) '${s['id']}/${(i as Map)['id']}': (s, i),
    };
    return [
      for (final h in ((p['history'] as List?) ?? const []).reversed.cast<Map>())
        {
          for (final e in h.entries)
            if (e.key != 'chat') e.key as String: e.value,
          'stall_name': items['${h['stall']}/${h['item']}']?.$1['name'] ?? h['stall'],
          'item_name': items['${h['stall']}/${h['item']}']?.$2['name'] ?? h['item'],
          'emoji': items['${h['stall']}/${h['item']}']?.$2['emoji'] ?? '🛒',
          'look': items['${h['stall']}/${h['item']}']?.$1['look'],
          'messages': (h['chat'] as List?)?.length ?? 0,
        },
    ];
  }

  /// One past haggle with its whole chat.
  Map<String, Object?>? historyItem(String id) {
    final h = ((p['history'] as List?) ?? const []).cast<Map>().where((x) => x['id'] == id).firstOrNull;
    if (h == null) return null;
    return {...history().firstWhere((x) => x['id'] == id), 'chat': h['chat']};
  }

  /// Rudeness costs friendship straight away.
  void rude(String stall) {
    _addPoints(stall, -10);
    _friend(stall)['rude'] = ((_friend(stall)['rude'] ?? 0) as num).toInt() + 1;
  }

  /// A stallholder's profile: hearts, and the bits of their story unlocked so far.
  Map<String, Object?> profile(String stall) {
    final s = _stalls[stall]!;
    final story = (s['story'] as List? ?? const []).cast<String>();
    final lvl = hearts(stall);
    return {
      'id': stall,
      'name': s['name'],
      'hearts': lvl,
      'points': points(stall),
      'next_at': lvl < 3 ? heartAt[lvl] : null,
      'story': [for (var i = 0; i < story.length; i++) i < lvl ? story[i] : null],
    };
  }
}
