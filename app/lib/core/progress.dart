/// The game around the haggles: friendship with each stallholder, Mum's daily shopping list and streak, stickers,
/// stall unlocks, tips and backstories. Everything lives in the player's profile on the phone.
library;

import 'dart:math' as math;

import 'arcs.dart';
import 'challenges.dart';
import 'legendary.dart';
import 'softspots.dart';
import 'treats.dart';

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
  ('sharp_eye', '🧐', 'Sharp eye', 'Guess the fair price within 10%, 5 times'),
  ('festive', '🏮', 'Festival week shopper', 'Close a deal during a festival week'),
  ('storyteller', '📖', 'Part of the story', "Finish a stallholder's story"),
  ('shopkeeper', '🧺', 'Shopkeeper', 'Sell at your own stall for the usual price or more'),
  ('saver', '🫙', 'Saved up', 'Buy something with your savings jar'),
  ('lucky', '🎁', 'Lucky customer', 'Get a freebie from a stallholder'),
  ('quotes5', '💬', 'Quote collector', 'Save 5 favourite lines'),
  ('teamwork', '👥', 'Teamwork', 'Close a deal together with a friend (live co-op)'),
  ('combo', '🤜', 'Tag team', 'Pull off a tag-team combo with a friend: one sweet-talks, the other offers'),
  ('legend', '✨', 'Legendary find', 'Buy a legendary item on the one day it shows up'),
];

String dayKey(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// A stable number from text, the same on every phone (for things everyone shares on a day).
int stableHash(String s) => _hash(s);

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

  /// How this customer haggled last time at this stall, in words (no numbers), so the stallholder can tease them.
  String howTheyHaggled(String stall) {
    final last = _haggles.lastWhere((h) => h['stall'] == stall, orElse: () => const {});
    final item = (_stalls[stall]?['items'] as List? ?? const []).cast<Map>().where((i) => i['id'] == last['item']);
    if (last.isEmpty || item.isEmpty) return '';
    if (last['result'] == 'walked') return 'Last time they walked away without buying; you may tease them about it.';
    if (last['result'] != 'deal' || last['deal'] == null) return '';
    final deal = (last['deal'] as num).toDouble();
    final i = item.first;
    if (deal <= (i['floor'] as num) * 1.06) {
      return 'Last time they bargained you down very hard; tease them that they always squeeze you.';
    }
    if (deal >= (i['ask'] as num) * 0.95) return 'Last time they paid close to your asking price without much fuss.';
    return 'Last time they bargained a little, fairly.';
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
        .map((i) => plainName('${i['name']}'))
        .firstOrNull;
    final name = playerName.replaceAll(RegExp(r'\d+'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim(); // number-free
    return [
      'You know this customer${lvl >= 2 && name.isNotEmpty ? ', $name' : ''}: they have come to your stall ${visits > 5 ? 'many times' : 'a few times'}.',
      if (lastItem != null) 'Last time they bought your $lastItem; you may ask how it was.',
      howTheyHaggled(stall),
      if (lvl >= 3) 'They are one of your favourite customers: be extra warm.',
      if (((f['rude'] ?? 0) as num) > 0 && lvl < 2) 'They were rude to you once; you remember.',
    ].where((x) => x.isNotEmpty).join(' ');
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

  /// The first stalls are open from the start; the others open with stars or days of play.
  bool isBaseStall(String stall) => unlockAt(stall) == 0 && unlockDays(stall) == 0;

  /// 🆕 A stall that has opened for this player and they haven't haggled at yet.
  bool isNewStall(String stall) =>
      !isBaseStall(stall) && unlocked(stall) && ((_friend(stall)['visits'] ?? 0) as num).toInt() == 0;

  /// A stall that opens on the player's next market day (only its day count is missing), or null.
  String? opensNextDay() => _stalls.keys
      .where((s) => !unlocked(s) && unlockDays(s) == daysPlayed() + 1 && bestStars() >= unlockAt(s))
      .firstOrNull;

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
      // Mum's nudge to a stall that opened for you and you haven't tried (the list itself stays everyone's)
      if (_stalls.keys.where(isNewStall).firstOrNull case final s?)
        'try': {'stall': s, 'name': _stalls[s]?['name'], 'item': ((_stalls[s]?['items'] as List).first as Map)['id']},
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

  /// A legendary item was bought: sold out for this player (counted by its day, or by its whole event).
  bool legendBought(String key) {
    final b = _map('legend')['bought'];
    return b == key || (b is List && b.contains(key));
  }

  void buyLegend(String key) {
    final m = _map('legend');
    final old = m['bought'];
    final list = [if (old is String) old, if (old is List) ...old.map((x) => '$x'), key];
    m['bought'] = list.length > 30 ? list.sublist(list.length - 30) : list;
  }

  /// Played (finished a haggle) on [day]?
  bool playedOn(String day) => _map('days').containsKey(day);

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
    if (deal && h['festival_week'] != null) _earn('festive', out);
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
    int toStock = -1, // how many go into your stock (default: all of them; Mum's go home to Mum)
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
    final story = _storyProgress(record, fresh);
    _addStock(record, toStock < 0 ? qty : toStock);
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
    // after the very first haggle: something to come back for
    final soon = (p['haggles'] as List).length == 1 ? opensNextDay() : null;
    return (
      stickers: fresh.toList(),
      mum: mum,
      unlocked: newly,
      notes: [...story, ...notes, if (soon != null) "🆕 Come back tomorrow: ${_stalls[soon]?['name']}'s stall opens!"],
    );
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
      // a legendary item from an event: its name stays in the history after the event is gone
      if (record['item_name'] != null) 'item_name': record['item_name'],
      if (record['emoji'] != null) 'emoji': record['emoji'],
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
      for (final s in content['stalls'] as List) ...{
        for (final i in (s as Map)['items'] as List) '${s['id']}/${(i as Map)['id']}': (s, i),
        for (final l in legendaryByStall[s['id']] ?? const <Map<String, Object>>[])
          '${s['id']}/${l['id']}': (s, l as Map),
      },
    };
    return [
      for (final h in ((p['history'] as List?) ?? const []).reversed.cast<Map>())
        {
          for (final e in h.entries)
            if (e.key != 'chat') e.key as String: e.value,
          'stall_name': items['${h['stall']}/${h['item']}']?.$1['name'] ?? h['stall'],
          'item_name': items['${h['stall']}/${h['item']}']?.$2['name'] ?? h['item_name'] ?? h['item'],
          'emoji': items['${h['stall']}/${h['item']}']?.$2['emoji'] ?? h['emoji'] ?? '🛒',
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
      if (arcs[stall] != null) 'arc': arc(stall),
      'soft_spot': softSpotFound(stall) ? softSpots[stall]?.topic : null,
    };
  }

  // ---------------------------------------------------------------- savings jar and goals
  double get jar => ((p['jar'] ?? 0) as num).toDouble();
  void addToJar(double v) => p['jar'] = ((jar + v) * 100).round() / 100;
  bool owns(String goal) => _map('goals')[goal] != null;

  List<Map<String, Object?>> goalsView() => [
    for (final g in goals)
      {
        'id': g.id,
        'emoji': g.emoji,
        'name': g.name,
        'cost': g.cost,
        'what': g.does,
        'tier': g.tier,
        'owned': owns(g.id),
        'can': !owns(g.id) && jar >= g.cost,
      },
  ];

  /// Spend from the jar on a goal. Returns what happens.
  String buyGoal(String id, Set<String> fresh) {
    final g = goals.where((x) => x.id == id).firstOrNull;
    if (g == null) throw ArgumentError('no such goal');
    if (owns(id)) throw StateError('You already have it!');
    if (jar < g.cost) throw StateError('Not enough in your jar yet: keep bargaining!');
    addToJar(-g.cost);
    _map('goals')[id] = dayKey(now());
    _earn('saver', fresh);
    return '${g.emoji} ${g.name}! ${g.bought}';
  }

  // ---------------------------------------------------------------- freebies
  /// A freebie into your stock (free). Every few good deals without one, one is guaranteed.
  /// [keepPaid] (with a wallet): never push out something you paid for; with no room, the freebie waits (the
  /// dry-spell count isn't reset, so it comes once there's room).
  String? maybeFreebie(
    String stall, {
    required bool lucky,
    required bool good,
    required Set<String> fresh,
    bool keepPaid = false,
  }) {
    final f = freebies[stall];
    if (f == null) return null;
    final pity = ((p['free_pity'] ?? 0) as num).toInt();
    if (!lucky && !(good && pity >= 3)) {
      if (good) p['free_pity'] = pity + 1;
      return null;
    }
    final list = (p['stock'] ??= <Object>[]) as List;
    if (keepPaid && list.length >= stockLimit) return null;
    p['free_pity'] = 0;
    list.add({
      'key': 'free:$stall',
      'name': f.$1,
      'emoji': f.$2,
      'cost': 0.0,
      'fair': f.$3,
      'from': _stalls[stall]?['name'],
    });
    if (list.length > stockLimit) list.removeRange(0, list.length - stockLimit);
    _earn('lucky', fresh);
    return '🎁 ${_stalls[stall]?['name']} threw in a ${f.$1} ${f.$2} for free! (Sell it at your own stall.)';
  }

  // ---------------------------------------------------------------- dilemmas
  /// You helped a stallholder out: friendship grows (within the daily cap).
  void helped(String stall) {
    _addPoints(stall, 8);
    final h = _map('helped');
    h[stall] = ((h[stall] ?? 0) as num).toInt() + 1;
  }

  // ---------------------------------------------------------------- quote book
  List<Map> get quotes => [for (final q in (p['quotes'] as List? ?? const [])) q as Map];

  /// Keep a favourite line. False if it's already there.
  bool saveQuote(String stall, String text, Set<String> fresh) {
    final t = text.trim().length > quoteMaxChars ? text.trim().substring(0, quoteMaxChars) : text.trim();
    if (t.isEmpty) return false;
    final list = (p['quotes'] ??= <Object>[]) as List;
    if (list.any((q) => (q as Map)['text'] == t)) return false;
    list.add({'stall': stall, 'name': _stalls[stall]?['name'] ?? stall, 'text': t, 'day': dayKey(now())});
    if (list.length > quotesKept) list.removeRange(0, list.length - quotesKept);
    if (list.length >= 5) _earn('quotes5', fresh);
    return true;
  }

  void removeQuote(String text) => (p['quotes'] as List?)?.removeWhere((q) => (q as Map)['text'] == text);

  // ---------------------------------------------------------------- soft spots
  /// Mark a stallholder's soft spot as found. True the first time.
  int softSpotsFound() => _map('soft_spots').values.where((v) => v == true).length;

  bool findSoftSpot(String stall) {
    final found = _map('soft_spots');
    if (found[stall] == true) return false;
    found[stall] = true;
    return true;
  }

  bool softSpotFound(String stall) => _map('soft_spots')[stall] == true;

  // ---------------------------------------------------------------- wallet
  /// Mum's money: to start with, then each new market day (an allowance, so saving is yours to do; topping up to a
  /// fixed amount would let you save it all every night and have it refilled).
  static const startMoney = 50.0;
  static const pocketMoney = 20.0;

  double get wallet => ((p['wallet'] ?? 0) as num).toDouble();
  void _setWallet(double v) => p['wallet'] = (math.max(0.0, v) * 100).round() / 100;

  /// A new market day: Mum's pocket money ([startMoney] the very first time, then [pocketMoney]). Once a day; returns
  /// what she gave.
  double topUp() {
    final day = dayKey(now());
    if (p['wallet_day'] == day) return 0;
    final add = p['wallet_day'] == null ? startMoney : pocketMoney;
    p['wallet_day'] = day;
    _setWallet(wallet + add);
    p['pocket'] = {'day': day, 'added': add};
    return add;
  }

  /// A new day you play: what your shop things do, once a day (Mum's cake, the piggy bank, deliveries). With no
  /// wallet, money goes into the jar instead. Returns this morning's summary (also when already done today).
  Map<String, Object?> newDay({required bool wallet}) {
    final day = dayKey(now());
    if (p['perks_day'] != day) {
      p['perks_day'] = day;
      void gain(double v) => wallet ? receive(v) : addToJar(v);
      final m = <String, Object?>{'day': day};
      if (owns('cake')) {
        gain(5);
        m['cake'] = 5.0;
      }
      if (owns('piggy') && jar > 0) {
        final interest = (math.min(5.0, jar * 0.02) * 100).floor() / 100;
        if (interest > 0) {
          addToJar(interest);
          m['interest'] = interest;
        }
      }
      // deliveries: the oldest things in your stock, at 90% of the market's price (a gift from a stallholder: its
      // fair price). More than you paid if you haggled well; less than a good customer at your own stall pays.
      final n = (owns('scooter') ? 1 : 0) + (owns('van') ? 2 : 0) + (owns('stall2') ? 3 : 0);
      final sent = <String>[];
      var total = 0.0;
      for (var i = 0; i < n && stock.isNotEmpty; i++) {
        final x = stock.first;
        final price = x['ask'] is num
            ? (((x['ask'] as num) * 0.9 * 2).round() / 2)
            : ((x['fair'] ?? x['cost'] ?? 0) as num).toDouble();
        (p['stock'] as List).removeAt(0);
        gain(price);
        total += price;
        sent.add('${x['emoji']} ${x['name']}');
      }
      if (sent.isNotEmpty) {
        m['delivered'] = sent;
        m['delivered_total'] = (total * 100).round() / 100;
      }
      p['morning'] = m;
    }
    final m = p['morning'];
    return m is Map && m['day'] == day ? Map<String, Object?>.from(m) : const {};
  }

  /// What Mum added this morning (0 if nothing, or not today).
  double pocketToday() {
    final x = p['pocket'];
    return x is Map && x['day'] == dayKey(now()) ? ((x['added'] ?? 0) as num).toDouble() : 0;
  }

  /// Paid at the market.
  void pay(double v) => _setWallet(wallet - v);

  /// Money in: a sale at your own stall, the change from Mum's list.
  void receive(double v) => _setWallet(wallet + v);

  /// From your wallet into your savings jar (for goals). Returns what was saved.
  double saveToJar(double amount) {
    final v = (math.min(math.max(0.0, amount), wallet) * 100).round() / 100;
    if (v <= 0) return 0;
    _setWallet(wallet - v);
    addToJar(v);
    return v;
  }

  /// Does Mum pay for this one? An item on her list today that hasn't been bought yet.
  bool mumPays(String stall, String item) {
    final key = '$stall/$item';
    final t = today();
    final onList = (t['items'] as List).any((i) => '${(i as Map)['stall']}/${i['item']}' == key);
    final bought = (_map('daily')['bought'] as Map?) ?? const {};
    return onList && !bought.containsKey(key);
  }

  /// Mum paid for one of her list items at [price] (after the haggle has been recorded). When both are done, you keep
  /// the change: what's left of her budget goes into your wallet (over budget, the extra comes out of it). Returns
  /// Mum's note about the change, once.
  String? mumPaid(String stall, String item, double price) {
    final d = _map('daily');
    final paid = (d['mum_paid'] ??= <String, Object?>{}) as Map;
    paid['$stall/$item'] = price;
    final t = today();
    final keys = [for (final i in (t['items'] as List).cast<Map>()) '${i['stall']}/${i['item']}'];
    if (d['change_given'] == true || !keys.every(paid.containsKey)) return null;
    d['change_given'] = true;
    final spent = keys.fold<double>(0, (a, k) => a + (paid[k] as num).toDouble());
    final change = (((t['budget'] as num).toDouble() - spent) * 100).round() / 100;
    if (change > 0) {
      receive(change);
      return '👛 Mum: Keep the change! ${_money(change)} into your wallet.';
    }
    if (change < 0) {
      final extra = math.min(-change, wallet);
      pay(extra);
      return extra > 0 ? '👛 Mum: You went over, so ${_money(extra)} comes out of your wallet ah.' : null;
    }
    return null;
  }

  // ---------------------------------------------------------------- stock for your own stall
  static const stockMax = 10; // to start with (a bigger shelf and a storeroom from the shop make room for more)

  /// How many things your stock holds: 10, 15 with the bigger shelf, 25 with the storeroom.
  int get stockLimit => owns('storeroom') ? 25 : (owns('shelf') ? 15 : stockMax);

  /// Would a deal on this item go into your stock? (Not a day's rental or a catering order, not a legendary item.)
  bool goesToStock(String stall, String item) =>
      !notForResale.contains('$stall/$item') &&
      (_stalls[stall]?['items'] as List? ?? const []).cast<Map>().any((i) => i['id'] == item);

  /// Room left in your stock.
  int get stockRoom => stockLimit - stock.length;

  /// Things that can't be resold at your own stall (a day's rental; a catering order).
  static const notForResale = {'tan/bicycle', 'rosnah/tray'};

  List<Map> get stock => [for (final x in (p['stock'] as List? ?? const [])) x as Map];

  /// A deal at the market: what you bought becomes stock for your own stall, at what you paid per piece.
  void _addStock(Map record, int qty) {
    if (record['result'] != 'deal' || record['deal'] == null) return;
    final key = '${record['stall']}/${record['item']}';
    if (notForResale.contains(key)) return;
    final item = (_stalls['${record['stall']}']?['items'] as List? ?? const [])
        .cast<Map>()
        .where((i) => i['id'] == record['item'])
        .firstOrNull;
    if (item == null) return;
    final list = (p['stock'] ??= <Object>[]) as List;
    for (var i = 0; i < qty; i++) {
      list.add({
        'key': key,
        'name': item['name'],
        'emoji': item['emoji'],
        'cost': (record['deal'] as num).toDouble(),
        'fair': (item['fair'] as num).toDouble(),
        'ask': (item['ask'] as num).toDouble(),
        'from': _stalls['${record['stall']}']?['name'],
      });
    }
    if (list.length > stockLimit) list.removeRange(0, list.length - stockLimit);
  }

  /// "Sell this next": your stall sells the first thing in your stock, so this one goes to the front.
  void stockToFront(int i) {
    final list = (p['stock'] as List?) ?? const [];
    if (i <= 0 || i >= list.length) return;
    list.insert(0, list.removeAt(i));
  }

  /// Sold at your own stall: one unit of it leaves your stock.
  void takeStock(String key, double cost) {
    final list = (p['stock'] as List?) ?? const [];
    final i = list.indexWhere((x) => (x as Map)['key'] == key && x['cost'] == cost);
    if (i >= 0) list.removeAt(i);
  }

  // ---------------------------------------------------------------- story arcs
  Map _arc(String stall) => (_map('arcs')[stall] ??= <String, Object?>{'done': 0}) as Map;

  /// A regular's story: each chapter done, open (with what to do) or locked (until more hearts).
  Map<String, Object?> arc(String stall) {
    final chapters = arcs[stall]!;
    final done = ((_arc(stall)['done'] ?? 0) as num).toInt();
    return {
      'title': arcTitles[stall],
      'chapters': [
        for (final (i, c) in chapters.indexed)
          {
            'title': c.title,
            'state': i < done ? 'done' : (i == done && hearts(stall) >= c.hearts ? 'open' : 'locked'),
            'text': i < done ? c.done : c.ask,
            'hearts': c.hearts,
          },
      ],
    };
  }

  /// After a haggle: did it finish the open chapter of anyone's story? (Auntie Mei's can need Uncle Lim's prawns.)
  List<String> _storyProgress(Map record, Set<String> fresh) {
    final notes = <String>[];
    for (final MapEntry(key: stall, value: chapters) in arcs.entries) {
      final a = _arc(stall);
      final n = ((a['done'] ?? 0) as num).toInt();
      if (n >= chapters.length || hearts(stall) < chapters[n].hearts) continue;
      if (!chapters[n].check(record, a['last'] as Map?)) continue;
      a['done'] = n + 1;
      a['last'] = {'day': record['day']};
      notes.add('📖 ${arcTitles[stall]}, chapter ${n + 1}: ${chapters[n].done}');
      if (n + 1 == chapters.length) _earn('storyteller', fresh);
    }
    return notes;
  }
}

/// An item's name without numbers, for notes to the AI (which may only say the game's own numbers):
/// "tray of kampung eggs (10)" -> "tray of kampung eggs".
String plainName(String name) =>
    name.replaceAll(RegExp(r'\s*\([^)]*\)'), '').replaceAll(RegExp(r'\d+'), '').replaceAll(RegExp(r'\s+'), ' ').trim();
