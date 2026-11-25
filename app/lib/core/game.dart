/// The whole game, on the phone: haggles, reading messages, the stallholders' lines, stats and reports.
/// Port of server/hh/api.py. Returns the same shapes the server did, so the screens didn't change.
/// The only network use is the optional AI endpoint (see ai_client.dart).
library;

import 'dart:convert';
import 'dart:math' as math;

import 'ai_client.dart';
import 'challenges.dart';
import 'engine.dart';
import 'festivals.dart';
import 'progress.dart';
import 'reader.dart';
import 'shop.dart';
import 'softspots.dart';
import 'treats.dart';
import 'voice.dart';

class GameError implements Exception {
  GameError(this.code, this.message);
  final int code;
  final String message;
  @override
  String toString() => message;
}

/// Somewhere to keep small text values (secure storage on the phone, a map in tests).
abstract class KeyValue {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

class MemoryKeyValue implements KeyValue {
  final data = <String, String>{};
  @override
  Future<String?> read(String key) async => data[key];
  @override
  Future<void> write(String key, String value) async => data[key] = value;
  @override
  Future<void> delete(String key) async => data.remove(key);
}

const nameMax = 20;

/// Letters (any language), numbers, spaces and . ' - only; spaces squeezed; at most [nameMax] characters.
/// Null if nothing is left or there's no letter in it.
String? cleanName(String raw) {
  var s = raw.replaceAll(RegExp(r"[^\p{L}\p{M}\p{N} .'\-]", unicode: true), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
  s = String.fromCharCodes(s.runes.take(nameMax)).trim();
  return RegExp(r'\p{L}', unicode: true).hasMatch(s) ? s : null;
}

const _adj = [
  'Shiok',
  'Steady',
  'Kiasu',
  'Atas',
  'Chill',
  'Lucky',
  'Sneaky',
  'Jolly',
  'Swee',
  'Cheeky',
  'Zesty',
  'Blur',
];
const _noun = [
  'Otter',
  'Kaya',
  'Pandan',
  'Satay',
  'Kopi',
  'Mango',
  'Durian',
  'Prata',
  'Rojak',
  'Kucing',
  'Laksa',
  'Chendol',
];

/// A stable number from text, so the same haggle moment always picks the same ready-made line.
int stableSeed(String s) {
  var h = 0x811c9dc5;
  for (final c in utf8.encode(s)) {
    h = ((h ^ c) * 0x01000193) & 0x7fffffff;
  }
  return h;
}

class _Session {
  _Session(this.id, this.stall, this.item, this.h, this.seed);
  final String id;
  final Map stall, item;
  final Haggle h;
  final int seed;
  final chat = <Map<String, Object?>>[];
  List<Map<String, Object?>> shown = []; // the suggestions on screen right now
  bool recorded = false;
  num? guess; // the player's guess at the fair price, before haggling (shown against it at the end)
  Festival? festival; // a festival week (real dates)
  int nice = 0; // friendly moves (compliments, "I'm a regular"): a little extra friendship
  int typed = 0, tapped = 0; // how the player played (for challenges)
  final tactics = <String>{}; // compliment, regular, competitor, bulk, plead, pity, budget...
  bool rude = false;
  bool calledBack = false;
  bool softSpot = false; // their soft spot came up this haggle (warms them once)
  String found = ''; // the soft spot just found for the first time (shown once)
  bool challenged = false; // they challenged the customer to convince them (the next typed message is the pitch)
  bool pitched = false; // a persuasion moment happened this haggle (at most one)
  int? pitchScore;
  String? dilemma; // a stallholder's small trouble, offered at the start (help from your jar, or not)
  Twist? twist; // a silly twist in the middle of the haggle, waiting for the player's choice
  bool twisted = false; // at most one a haggle
  String twistNote = ''; // what happened, for the AI's next reply
  Map<String, Object?> finish = const {}; // new stickers, Mum's note, unlocks (when it ends)
}

/// The short banner shown during a haggle with a market surprise.
String surpriseNote(String event, String name, int rivalLeft) => switch (event) {
  'rain' => '🌧️ Rainy day: the market is empty and $name is keen to sell!',
  'closing' => "⏰ Closing time: $name wants to clear stock, but she's tired. Be quick!",
  'festival' => '🎉 Festival day: prices are up, everyone is cheerful!',
  'rival' =>
    rivalLeft > 0
        ? '👵 Auntie Rose wants the last one too: $rivalLeft move${rivalLeft == 1 ? '' : 's'} left!'
        : '👵 Auntie Rose got it…',
  _ => '',
};

/// What the AI is told about a surprise (number-free, so its reply passes the price check).
String surpriseForAi(String event, int rivalLeft) => switch (event) {
  'rain' => "It's raining and the market is empty: you're keen to make a sale.",
  'closing' => "It's nearly closing time: you want to clear your stock, but you're tired.",
  'festival' => "It's a festival day: the market is busy and cheerful, and your prices are higher today.",
  'rival' =>
    rivalLeft == 1
        ? 'Another customer, Auntie Rose, is about to buy this last one: warn them it is now or never.'
        : 'Another customer, Auntie Rose, also wants this last one: now and then hurry the customer along.',
  _ => '',
};

class Game {
  Game({
    required this.content,
    required this.store,
    AiClient? ai,
    math.Random? random,
    DateTime Function()? now,
    this.unlockAll = false,
    this.surprises = true,
  }) : ai = ai ?? AiClient(const AiConfig()),
       _rnd = random ?? math.Random.secure(),
       now = now ?? DateTime.now;

  final DateTime Function() now;
  final bool unlockAll; // tests: every stall open
  final bool surprises; // tests: no random market surprises
  Progress get progress => Progress(_profile, content, now);

  final Map content;
  final KeyValue store;
  AiClient ai;
  final math.Random _rnd;
  final _sessions = <String, _Session>{};
  Map<String, Object?> _profile = {};

  Map<String, Map> get _stalls => {for (final s in content['stalls'] as List) (s as Map)['id'] as String: s};
  Map get _playerLines => content['player'] as Map;

  // ---------------------------------------------------------------- profile (kept on the phone)
  /// Where the progress lives in [store]: 'profile' for playing without an account, another key for each account's
  /// copy (the account's server keeps the real one).
  String profileKey = 'profile';

  /// Called after every save (the account copy is sent to the server a moment later).
  void Function()? onSaved;

  /// Switch to another profile: haggles in progress are dropped.
  Future<void> useProfile(String key) async {
    _sessions.clear();
    profileKey = key;
    await load();
  }

  /// The progress as text (to keep it on the account's server), and back.
  String exportProfile() => jsonEncode(_profile);
  Future<void> importProfile(String raw) async {
    _sessions.clear();
    if (raw.trim().isEmpty) {
      await store.delete(profileKey);
    } else {
      await store.write(profileKey, raw);
    }
    await load();
  }

  /// Finished haggles in this profile (0: nothing worth keeping yet).
  int get haggleCount => _done.length;

  Future<void> load() async {
    final raw = await store.read(profileKey);
    _profile = raw == null ? {} : Map<String, Object?>.from(jsonDecode(raw) as Map);
    if (_profile['name'] == null) {
      _profile = {'name': randomName(), 'haggles': <Object>[], 'reports': <Object>[]};
    }
    progress.migrate(); // older profiles get the new parts, with credit for past haggles
    await _save();
  }

  /// A fun made-up name, offered on first launch (and by the 🎲 button).
  String randomName() =>
      '${_adj[_rnd.nextInt(_adj.length)]} ${_noun[_rnd.nextInt(_noun.length)]} ${_rnd.nextInt(900) + 100}';

  /// The player picks their own name (it goes into the AI's notes, so only letters, numbers, spaces and . ' -).
  Future<String> setName(String raw) async {
    final name = cleanName(raw);
    if (name == null) throw GameError(400, 'Pick a name with some letters in it.');
    _profile['name'] = name;
    _profile['named'] = true;
    await _save();
    return name;
  }

  bool get hard => _profile['hard'] == true;
  Future<void> setHard(bool on) async {
    _profile['hard'] = on;
    await _save();
  }

  Map<String, Object?> today() => progress.today();
  List<Map<String, Object?>> history() => progress.history();
  Map<String, Object?> challenges() => Challenges(progress).summary();
  Map<String, Object?> historyItem(String id) =>
      progress.historyItem(id) ?? (throw GameError(404, 'That haggle is no longer kept'));
  List<Map<String, Object?>> stickers() => progress.stickers();
  Map<String, Object?> stallProfile(String id) {
    if (_stalls[id] == null) throw GameError(404, 'No such stall');
    return progress.profile(id);
  }

  Future<void> _save() async {
    await store.write(profileKey, jsonEncode(_profile));
    onSaved?.call();
  }

  List<Map> get _done => [for (final h in (_profile['haggles'] as List? ?? const [])) h as Map];
  List<Map> get reports => [for (final r in (_profile['reports'] as List? ?? const [])) r as Map];

  Map<String, Object?> me() {
    final done = _done;
    return {
      'name': _profile['name'],
      'named': _profile['named'] == true,
      'festival': festivalWeek?.toJson(),
      'haggles': done.length,
      'deals': done.where((h) => h['result'] == 'deal').length,
      'stars': done.fold<int>(0, (a, h) => a + ((h['stars'] ?? 0) as num).toInt()),
      'best_saved': done.fold<double>(0, (a, h) => math.max(a, ((h['saved'] ?? 0) as num).toDouble())),
      'best_stars': progress.bestStars(),
      'streak': progress.streak(),
      'stickers': progress.stickers().where((x) => x['earned'] != null).length,
      'rank': Challenges(progress).rank(),
      'days_played': progress.daysPlayed(),
    };
  }

  Map<String, Object?> stalls() {
    final best = <String, int>{};
    for (final h in _done) {
      final k = '${h['stall']}/${h['item']}';
      best[k] = math.max(best[k] ?? 0, ((h['stars'] ?? 0) as num).toInt());
    }
    return {
      'stalls': [
        for (final s in content['stalls'] as List)
          {
            'id': s['id'],
            'name': s['name'],
            'stall': s['stall'],
            'place': s['place'],
            'look': s['look'],
            'hearts': progress.hearts(s['id'] as String),
            'locked': !progress.unlocked(s['id'] as String),
            'unlock_at': progress.unlockAt(s['id'] as String),
            'unlock_days': progress.unlockDays(s['id'] as String),
            'items': [
              for (final i in s['items'] as List)
                {
                  'id': i['id'],
                  'name': i['name'],
                  'emoji': i['emoji'],
                  'ask': i['ask'],
                  'stars': best['${s['id']}/${i['id']}'] ?? 0,
                },
            ],
          },
      ],
    };
  }

  /// Delete my data: everything this app kept on the phone.
  Future<void> deleteAll() async {
    _sessions.clear();
    await store.delete(profileKey);
    await load();
  }

  // ---------------------------------------------------------------- helpers
  String _line(
    Map stall,
    Map item,
    String event,
    Haggle h, {
    double? offer,
    required int seed,
    List<Map> chat = const [],
  }) {
    final lines = stall['lines'] as Map;
    final options = [for (final o in (lines[event] ?? lines['smalltalk']) as List) '$o'];
    final price = money(h.s.deal ?? h.s.pending ?? h.s.ask);
    final fmt = [
      for (final o in options)
        o.replaceAll('{item}', '${item['name']}').replaceAll('{price}', price).replaceAll('{offer}', money(offer)),
    ];
    final said = {
      for (final m in chat)
        if (m['who'] == 'them') m['text'],
    };
    final fresh = fmt.where((t) => !said.contains(t)).toList();
    final pool = fresh.isEmpty ? fmt : fresh;
    return pool[math.Random(stableSeed('$seed-${h.s.rounds}-$event')).nextInt(pool.length)];
  }

  String _playerText(String move, double? price, String seed, [String who = 'boss']) {
    final options = (_playerLines[move] ?? _playerLines['smalltalk']) as List;
    return '${options[math.Random(stableSeed(seed)).nextInt(options.length)]}'
        .replaceAll(r'${price}', money(price))
        .replaceAll('{who}', who);
  }

  String _who(_Session ss) => '${ss.stall['address'] ?? 'boss'}';

  /// What the AI should know beyond the chat: the market surprise and how well she knows this customer.
  String _notes(_Session ss, [String extra = '']) => [
    ss.festival?.wish ?? '',
    surpriseForAi(ss.h.s.event, ss.h.s.rivalLeft),
    progress.memoryNote('${ss.stall['id']}', '${_profile['name']}'),
    extra,
  ].where((x) => x.isNotEmpty).join(' ');

  List<Map<String, Object?>> _suggestions(_Session ss) => [
    for (final (i, s) in ss.h.suggestions().indexed)
      {
        'move': s['move'],
        'price': s['price'],
        'text': _playerText(s['move'] as String, s['price'] as double?, '${ss.id}-${ss.h.s.rounds}-$i', _who(ss)),
      },
  ];

  /// What a typed message means. Plain offers and a bare yes take the fast path (no AI reading); a price described
  /// in words is worked out here from the real prices, never by the model.
  Future<Heard> _read(String text, _Session ss) async {
    final h = ss.h;
    final base = h.s.pending ?? h.s.ask;
    Heard heard;
    final fast = fastOffer(text, base);
    if (fast != null) {
      heard = Heard('offer', fast, reading: 'plain offer');
    } else if (h.s.pending != null && plainYes(text)) {
      heard = const Heard('accept', null, reading: 'plain yes');
    } else if (ai.enabled) {
      heard = await ai.understand(
        text,
        history: ss.chat,
        ask: h.s.ask,
        item: '${ss.item['name']}',
        name: '${ss.stall['name']}',
        pending: h.s.pending,
        lastOffer: h.s.lastOffer,
        qty: h.s.qty,
      );
    } else {
      heard = heardByRules(text);
    }
    if (heard.relOp.isNotEmpty) {
      double? price;
      if (heard.relOp == 'less' && heard.relAmount != null && heard.relAmount != 0) {
        price = base - heard.relAmount!;
      } else if (heard.relOp == 'halfway' && h.s.lastOffer != null && h.s.lastOffer != 0) {
        price = (base + h.s.lastOffer!) / 2;
      } else if (heard.relOp == 'round_down') {
        price = base != base.floorToDouble() ? base.floorToDouble() : ((base / 5).ceil() - 1) * 5.0;
      }
      if (price == null || price <= 0) {
        return heard.copyWith(move: 'clarify', clearPrice: true, unclear: 'what price they want to pay');
      }
      heard = heard.copyWith(move: heard.move == 'budget' ? 'budget' : 'offer', price: price);
    }
    if (heard.qty != null && heard.qty! > 2 && (heard.move == 'bulk' || heard.move == 'offer')) {
      final perPiece = heard.price != null && heard.per == 'total' ? heard.price! / heard.qty! : heard.price;
      return Heard(
        'bulk',
        perPiece,
        ai: heard.ai,
        reading: heard.reading,
        also: heard.also,
        per: 'each',
        qty: heard.qty,
      );
    }
    if (heard.move == 'offer' && heard.price != null && heard.per == 'total' && h.s.qty > 1) {
      heard = heard.copyWith(price: heard.price! / 2); // "two cases, 14" while buying two: $7 each
    }
    if (heard.move == 'bulk' && heard.price != null && heard.price != 0) {
      if (heard.per == 'total') {
        heard = heard.copyWith(price: heard.price! / 2);
      } else if (heard.per != 'each') {
        return heard.copyWith(move: 'clarify', clearPrice: true, unclear: 'whether the price is for both or each');
      }
    }
    return heard;
  }

  Map<String, Object?> _view(_Session ss, String said, String event, Outcome? out, String? you, bool aiLine) {
    final h = ss.h;
    ss.shown = _suggestions(ss);
    return {
      'id': ss.id,
      'stall': ss.stall['id'],
      'item': ss.item['id'],
      'event': event,
      'line': said,
      'ai_line': aiLine,
      'you_said': you,
      'ask': h.s.ask,
      'opening': h.s.opening,
      'patience': math.max(0, h.s.patience.round()),
      'mood': (h.s.mood * 10).round() / 10,
      'qty': h.s.qty,
      'done': h.s.done,
      'result': h.s.result,
      'deal': h.s.deal,
      'pending': h.s.pending,
      'stars': out?.stars ?? 0,
      'saved': out?.saved ?? 0.0,
      'suggestions': hard ? const <Object>[] : ss.shown, // hard mode: no suggestions, just you
      'surprise': h.s.event,
      'surprise_note': h.s.event == 'festival' && ss.festival != null
          ? '${ss.festival!.emoji} ${ss.festival!.name}: prices are up, everyone is cheerful!'
          : surpriseNote(h.s.event, '${ss.stall['name']}', h.s.rivalLeft),
      'guess': ss.guess,
      'found': _takeFound(ss), // a soft spot found just now (once)
      'challenge': ss.challenged, // "convince me!": the next typed message is a pitch
      'pitch_score': ss.pitchScore,
      'closeness': h.s.done && h.s.result == 'deal' && h.s.deal != null ? _closeness(ss) : null,
      'dilemma': ss.dilemma == null
          ? null
          : {
              'text': dilemmas[ss.dilemma]!.$1,
              'cost': dilemmas[ss.dilemma]!.$2,
              'can': progress.jar >= dilemmas[ss.dilemma]!.$2,
            },
      'jar': progress.jar,
      'twist': ss.twist == null
          ? null
          : {
              'text': _fillTwist(ss.twist!.text, ss),
              'options': [for (final o in ss.twist!.options) o.$1],
            },
      'rival_left': h.s.rivalLeft,
      'hearts': progress.hearts('${ss.stall['id']}'),
      'new_stickers': ss.finish['stickers'] ?? const <Object>[],
      'mum': ss.finish['mum'],
      'unlocked': ss.finish['unlocked'] ?? const <Object>[],
      'notes': ss.finish['notes'] ?? const <Object>[],
      'accept_text': _playerText('accept', h.s.ask, ss.id, _who(ss)),
      'walk_text': _playerText('walk', null, ss.id, _who(ss)),
    };
  }

  /// Where a stock item was bought (its stallholder), for the shop screen.
  String? _stockFrom(String productId) {
    for (final x in progress.stock) {
      if ('stock:${x['key']}' == productId) return '${x['from']}';
    }
    return null;
  }

  String? _takeFound(_Session ss) {
    final f = ss.found;
    ss.found = '';
    return f.isEmpty ? null : f;
  }

  /// After a deal: how close it came to the stallholder's real limit, in words (never the number). Measured like
  /// the stars, against the secret lowest price; a good mood could have gone a little further.
  String _closeness(_Session ss) {
    final h = ss.h;
    final floor = h.item.floor;
    final r = h.s.deal! / floor;
    final who = '${ss.stall['name']}';
    var t = r <= 1.03
        ? "🎯 Right at $who's limit!"
        : (r <= 1.10
              ? "📏 Very close to $who's limit."
              : (r <= 1.25
                    ? '📏 There was still some room left.'
                    : '📏 There was lots of room left: try lower next time!'));
    if (r > 1.03 && h.floorNow() < floor * 0.97) t += ' In such a good mood, $who might have gone a little lower.';
    return t;
  }

  // ---------------------------------------------------------------- the game
  Future<Map<String, Object?>> start(String stallId, [String? itemId, String? surprise]) async {
    final stall = _stalls[stallId];
    if (stall == null) throw GameError(404, 'No such stall');
    if (!unlockAll && !progress.unlocked(stallId)) {
      throw GameError(
        403,
        progress.unlockDays(stallId) > 0
            ? '${stall['name']} opens on day ${progress.unlockDays(stallId)} of your Market Month.'
            : 'Unlock ${stall['name']} with ${progress.unlockAt(stallId)} ⭐ (best on each item).',
      );
    }
    // About 1 haggle in 3 has a market surprise; in a festival week, festival days are much more common.
    final fest = festivalWeek;
    if (!surprises) surprise ??= '';
    surprise ??= fest == null
        ? switch (_rnd.nextInt(100)) {
            < 9 => 'rain',
            < 18 => 'closing',
            < 26 => 'festival',
            < 34 => 'rival',
            _ => '',
          }
        : switch (_rnd.nextInt(100)) {
            < 5 => 'rain',
            < 10 => 'closing',
            < 40 => 'festival',
            < 46 => 'rival',
            _ => '',
          };
    if (surprise == 'none') surprise = ''; // tests: no surprise on purpose
    final items = stall['items'] as List;
    final item = (items.firstWhere((i) => (i as Map)['id'] == itemId, orElse: () => items.first)) as Map;
    final seed = _rnd.nextInt(1 << 31);
    final id = '${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}${_rnd.nextInt(1 << 20).toRadixString(36)}';
    final ss = _Session(
      id,
      stall,
      item,
      Haggle(
        Item.fromJson(item),
        Personality.fromJson(stall['personality'] as Map),
        seed: seed,
        event: surprise,
        friend: progress.hearts(stallId),
      ),
      seed,
    );
    ss.festival = fest;
    // now and then a friend has a small trouble (a choice with a cost); never in tests without surprises
    if (surprises &&
        surprise != 'rival' &&
        progress.hearts(stallId) >= 1 &&
        dilemmas[stallId] != null &&
        stableSeed('$seed-dilemma') % 6 == 0) {
      ss.dilemma = stallId;
    }
    _sessions[id] = ss;
    String? said;
    final heard = gossipNote(stallId);
    if (ai.enabled && (surprise.isNotEmpty || fest != null || heard.isNotEmpty || progress.hearts(stallId) > 0)) {
      // A friend, a surprise, a festival week or some gossip: worth a fresh greeting from the AI.
      said = await ai.say(
        stall: stall,
        item: item,
        event: 'greet',
        numbers: {'ask': ss.h.s.ask},
        note: _notes(ss, heard),
      );
    }
    final aiLine = said != null;
    if (said == null) {
      said = _line(stall, item, surprise.isEmpty ? 'greet' : 'greet_$surprise', ss.h, seed: seed);
      final opener = _gossipOpener(stallId);
      if (opener != null) said = '$opener $said';
    }
    ss.chat.add({'who': 'them', 'text': said, 'ask': ss.h.s.ask, if (aiLine) 'ai': true});
    return _view(ss, said, 'greet', null, null, aiLine);
  }

  Future<Map<String, Object?>> move(String id, {int? pick, String? move, String? text}) async {
    final ss = _sessions[id];
    if (ss == null) throw GameError(404, 'No such haggle');
    final h = ss.h;
    if (h.s.done) throw GameError(409, 'This haggle is over');
    final stall = ss.stall, item = ss.item;
    final useAi = ai.enabled; // every move, typed or tapped, is part of the conversation
    var readAi = false;
    var unclear = '';
    var heard = const Heard('smalltalk', null);
    String kind;
    double? price;
    String you;
    ss.twist = null; // a twist left unanswered just passes
    final typed = text?.trim() ?? '';
    if (typed.isNotEmpty) {
      ss.typed++;
    } else if (pick != null) {
      ss.tapped++;
    }
    if (typed.isNotEmpty) {
      final t = typed.length > 300 ? typed.substring(0, 300) : typed;
      heard = await _read(t, ss);
      kind = heard.move;
      price = heard.price;
      readAi = heard.ai;
      unclear = heard.unclear;
      you = t;
    } else if (move == 'confirm' || move == 'cancel') {
      kind = move!;
      you = kind == 'confirm' && h.s.pending != null ? 'Deal! ${money(h.s.pending)}' : 'Wait, let me think first.';
    } else if (move == 'buy') {
      kind = 'buy';
      you = _playerText('accept', h.s.pending ?? h.s.ask, '$id-${h.s.rounds}-x', _who(ss));
    } else if (move == 'walk' || move == 'accept') {
      kind = move!;
      you = _playerText(kind, kind == 'accept' ? h.s.ask : null, '$id-${h.s.rounds}-x', _who(ss));
    } else if (pick != null) {
      if (hard || pick < 0 || pick >= ss.shown.length) throw GameError(400, 'No such suggestion');
      final s = ss.shown[pick];
      kind = s['move'] as String;
      price = s['price'] as double?;
      you = s['text'] as String;
    } else {
      throw GameError(400, 'Send pick, move or text');
    }
    if (h.s.pending != null &&
        typed.isNotEmpty &&
        ((kind == 'accept' && !(price != null && price != 0 && price < h.s.pending!)) ||
            (!readAi && plainYes(typed)))) {
      kind = 'confirm'; // a typed yes to "deal at $X, confirm?"
    }
    if (kind == 'accept' && price != null && price != 0 && price < h.s.ask) {
      kind = 'offer'; // "ok 24 lah" while they ask 26 is an offer of 24
    }
    Outcome? out;
    String event;
    if (kind == 'clarify') {
      event = 'clarify'; // ask back; nothing changes
    } else {
      if (heard.also.isNotEmpty && !const ['accept', 'confirm', 'walk', 'buy', 'cancel'].contains(kind)) {
        h.side(heard.also); // "so nice, 20 can?": the compliment counts too (within its limits)
      }
      // a soft spot: they love talking about it (once a haggle; found for the profile the first time)
      final spot = softSpots['${stall['id']}'];
      if (typed.isNotEmpty && !ss.softSpot && spot != null && spot.heardIn(typed) && kind != 'rude') {
        ss.softSpot = true;
        h.warm(1.2);
        ss.nice++;
        if (progress.findSoftSpot('${stall['id']}')) ss.found = spot.topic;
      }
      // a persuasion moment: the AI scores the pitch, and a good one warms them (once a haggle, within limits)
      if (ss.challenged) {
        ss.challenged = false;
        if (typed.isNotEmpty && kind != 'rude') {
          final score = await ai.judgePitch(stall: stall, item: item, pitch: typed) ?? 0;
          ss.pitchScore = score;
          h.warm(0.9 * score);
          if (score > 0) ss.nice++;
        }
      }
      bool? callBack;
      if (kind == 'walk' && ai.enabled && h.canCallBack()) {
        // Walking away: the AI judges whether this is the right moment for a final-final price.
        callBack = await ai.callBack(
          stall: stall,
          item: item,
          history: ss.chat,
          ask: h.s.ask,
          lastOffer: h.s.lastOffer,
        );
      }
      out = h.move(kind, price, callBack);
      event = out.event;
      if (event == 'callback') ss.calledBack = true;
      if (const ['compliment', 'regular', 'competitor', 'bulk', 'plead', 'pity', 'budget'].contains(kind)) {
        ss.tactics.add(kind);
      }
      if (heard.also.isNotEmpty) ss.tactics.add(heard.also);
      if (const ['flattered', 'regular'].contains(event) || const ['compliment', 'regular'].contains(heard.also)) {
        ss.nice++;
      }
      if ((kind == 'rude' || heard.also == 'rude') && !ss.rude) {
        ss.rude = true;
        progress.rude('${stall['id']}'); // she remembers
      }
    }
    String? said;
    var aiLine = false;
    // A persuasion moment now and then (about 1 haggle in 4, after a couple of moves), only with the AI, never in a
    // rush (Auntie Rose, low patience). Decided from the haggle's own seed, so it never touches the game's dice.
    final challengeNow =
        useAi &&
        !h.s.done &&
        !ss.pitched &&
        !ss.challenged &&
        h.s.rounds == 2 &&
        h.s.event != 'rival' &&
        h.s.patience > 50 &&
        stableSeed('${ss.seed}-pitch') % 4 == 0;
    if (useAi) {
      said = await ai.say(
        stall: stall,
        item: item,
        event: event,
        // a "no sale" ending mentions no price at all
        numbers: const ['refuse', 'letgo', 'rival_bought'].contains(event)
            ? const <String, double?>{}
            : {'ask': h.s.ask, 'offer': out?.offer, 'deal': h.s.deal ?? h.s.pending},
        history: ss.chat,
        heard: you,
        alsoOk: [
          for (final m in ss.chat)
            if (m['ask'] != null) m['ask'] as num,
          h.s.opening,
        ],
        unclear: unclear,
        budget: h.s.budget,
        patience: h.s.patience,
        also: heard.also,
        note: _notes(
          ss,
          [
            if (heard.qty != null && heard.qty! > 2)
              'They asked for ${heard.qty}; you only have two left today, so say you can sell them two (prices are per piece).',
            if (ss.softSpot && ss.chat.where((m) => m['soft_spot'] == true).isEmpty)
              'They just talked about ${softSpots['${stall['id']}']!.topic}, your favourite subject: you warm up to them a lot.',
            if (ss.pitchScore != null && ss.chat.where((m) => m['pitch'] == true).isEmpty)
              const [
                'Their pitch did not impress you: say so playfully.',
                'Their pitch was a fair try: you soften a little.',
                'Their pitch really won you over: say so warmly.',
              ][ss.pitchScore!],
            if (challengeNow) 'End your reply by challenging them, in one short sentence, to convince you why you should give them a better price.',
            if (ss.twistNote.isNotEmpty) '${ss.twistNote} React to it in character, briefly.',
          ].join(' '),
        ),
      );
      aiLine = said != null;
      if (challengeNow && aiLine) {
        ss.challenged = true; // only when the reply really contains the challenge
        ss.pitched = true;
      }
    }
    ss.twistNote = '';
    // a silly twist now and then, a few moves in (never without surprises, with Auntie Rose, at low patience, or
    // while a pitch is pending); decided from the haggle's own seed, never the game's dice
    if (surprises &&
        !ss.twisted &&
        !h.s.done &&
        h.s.rounds == 3 &&
        h.s.event != 'rival' &&
        h.s.patience > 40 &&
        !ss.challenged &&
        stableSeed('${ss.seed}-twist') % 100 < twistChance) {
      ss.twisted = true;
      ss.twist = twists[stableSeed('${ss.seed}-which') % twists.length];
    }
    said ??= _line(stall, item, event, h, offer: out?.offer, seed: ss.seed, chat: ss.chat);
    ss.chat.add({
      'who': 'you',
      'text': you,
      'move': kind,
      if (heard.reading.isNotEmpty || heard.also.isNotEmpty) ...{'reading': heard.reading, 'also': heard.also},
      if (ss.softSpot && ss.chat.where((m) => m['soft_spot'] == true).isEmpty) 'soft_spot': true,
      if (ss.pitchScore != null && ss.chat.where((m) => m['pitch'] == true).isEmpty) 'pitch': true,
    });
    ss.chat.add({'who': 'them', 'text': said, 'ask': h.s.ask, if (aiLine) 'ai': true});
    if (h.s.done && !ss.recorded) {
      ss.recorded = true;
      final r = progress.finish(
        record: {
          'stall': stall['id'],
          'item': item['id'],
          'result': h.s.result,
          'deal': h.s.deal,
          'stars': out?.stars ?? 0,
          'saved': out?.saved ?? 0.0,
          'event': h.s.event,
          'at': now().toIso8601String(),
          'day': dayKey(now()),
          'qty': h.s.qty,
          'moves': h.s.rounds,
          'typed': ss.typed,
          'tapped': ss.tapped,
          'tactics': ss.tactics.toList(),
          'patience': h.s.patience.round(),
          'called_back': ss.calledBack,
          'hard': hard,
          'rude': ss.rude,
          if (ss.guess != null) 'guess': ss.guess,
          if (ss.festival != null) 'festival_week': ss.festival!.id,
        },
        qty: h.s.qty,
        flags: {'nice': ss.nice, 'called_back': ss.calledBack, 'hard': hard},
        chat: ss.chat,
      );
      final extra = <String>[];
      final fresh = <String>{...r.stickers};
      if (h.s.result == 'deal' && h.s.deal != null) {
        // every dollar knocked off the first asking price goes into the savings jar
        final kept = ((h.s.opening - h.s.deal!) * h.s.qty * 100).round() / 100;
        if (kept > 0) {
          progress.addToJar(kept);
          extra.add('🫙 ${money(kept)} into your savings jar (${money(progress.jar)} saved).');
        }
        // a stallholder who likes you might throw something in (never in tests without surprises)
        if (surprises) {
          final chance = math.min(50, 12 + 10 * ss.nice + 5 * progress.hearts('${stall['id']}'));
          final free = progress.maybeFreebie(
            '${stall['id']}',
            lucky: stableSeed('${ss.seed}-free') % 100 < chance,
            good: (out?.stars ?? 0) >= 2 || ss.nice > 0,
            fresh: fresh,
          );
          if (free != null) extra.add(free);
        }
      }
      ss.finish = {
        'stickers': fresh.toList(),
        'mum': r.mum,
        'unlocked': r.unlocked,
        'notes': [...r.notes, ...extra],
      };
      await _save();
    } else if (ss.rude) {
      await _save();
    }
    return _view(ss, said, event, out, you, aiLine);
  }

  /// Twists: about one haggle in four (tests and tools can raise it). Never without surprises.
  int twistChance = 25;

  /// The player's choice in a twist: it changes only the stallholder's mood. Returns their reaction.
  Future<String> answerTwist(String id, int choice) async {
    final ss = _sessions[id];
    if (ss == null) throw GameError(404, 'No such haggle');
    final t = ss.twist;
    if (t == null || choice < 0 || choice >= t.options.length) throw GameError(400, 'Nothing to choose');
    ss.twist = null;
    final o = t.options[choice];
    ss.h.warm(o.$2);
    if (o.$2 > 0.5) ss.nice++;
    ss.twistNote = '${t.ai} ${o.$4}';
    return _fillTwist(o.$3, ss);
  }

  String _fillTwist(String s, _Session ss) =>
      s.replaceAll('{name}', '${ss.stall['name']}').replaceAll('{item}', '${ss.item['name']}');

  /// The stallholder's small trouble: help (from your jar, for friendship) or not. Returns what happened.
  Future<String> answerDilemma(String id, {required bool help}) async {
    final ss = _sessions[id];
    if (ss == null) throw GameError(404, 'No such haggle');
    final st = ss.dilemma;
    if (st == null) throw GameError(400, 'Nothing to answer');
    ss.dilemma = null;
    if (!help) return '';
    final cost = dilemmas[st]!.$2;
    if (progress.jar < cost) throw GameError(400, 'Not enough in your savings jar.');
    progress.addToJar(-cost);
    progress.helped(st);
    await _save();
    return '💛 ${ss.stall['name']} is touched: "You\'re a good one."';
  }

  /// The savings jar and what you can save up for.
  Map<String, Object?> jar() => {'jar': progress.jar, 'goals': progress.goalsView()};

  Future<Map<String, Object?>> buyGoal(String id) async {
    final fresh = <String>{};
    try {
      final note = progress.buyGoal(id, fresh);
      await _save();
      return {'note': note, 'jar': progress.jar, 'new_stickers': fresh.toList()};
    } on StateError catch (e) {
      throw GameError(400, e.message);
    } on ArgumentError {
      throw GameError(404, 'No such goal');
    }
  }

  /// The book of favourite lines.
  List<Map> quotes() => progress.quotes.reversed.toList();

  Future<bool> saveQuote(String stallId, String text) async {
    if (_stalls[stallId] == null) throw GameError(404, 'No such stall');
    final fresh = <String>{};
    final added = progress.saveQuote(stallId, text, fresh);
    if (added) await _save();
    return added;
  }

  Future<void> removeQuote(String text) async {
    progress.removeQuote(text);
    await _save();
  }

  /// Before haggling: the player guesses the fair price (it's shown against the real one when the haggle ends).
  Future<void> guess(String id, num price) async {
    final ss = _sessions[id];
    if (ss == null) throw GameError(404, 'No such haggle');
    if (ss.h.s.done) throw GameError(400, 'This haggle is over');
    if (price <= 0 || price > 100000) throw GameError(400, 'Guess a price in dollars.');
    ss.guess = (price * 100).round() / 100;
  }

  /// Friends' recent deals, by stall (from the account's market server): the stallholder may mention them.
  /// Each: {name, item, day}. Never with prices.
  Map<String, List<Map>> gossip = {};

  /// What the stallholder has heard: a friend who came by lately, or that this customer was rude next door today.
  String gossipNote(String stallId) {
    final parts = <String>[];
    final friends = gossip[stallId] ?? const [];
    if (friends.isNotEmpty) {
      final f = friends.first;
      final name = (cleanName('${f['name']}') ?? '')
          .replaceAll(RegExp(r'\d+'), ' ')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
      final item = ((_stalls[stallId]?['items'] as List? ?? const []).cast<Map>())
          .where((i) => i['id'] == f['item'])
          .map((i) => '${i['name']}')
          .firstOrNull;
      if (name.isNotEmpty && item != null) {
        final today = dayKey(now());
        final when = f['day'] == today ? 'earlier today' : 'a day or two ago';
        parts.add(
          'A friend of this customer (their name is "$name") bought the $item here $when. You may mention it in '
          'passing, without saying what they paid, and without guessing whether they are a man or a woman.',
        );
      }
    }
    final rudeAt = <String>{
      for (final h in (_profile['haggles'] as List? ?? const []).cast<Map>())
        if (h['rude'] == true && h['day'] == dayKey(now()) && h['stall'] != stallId)
          '${_stalls['${h['stall']}']?['name']}',
    };
    if (rudeAt.isNotEmpty) {
      parts.add(
        'Word travels at the market: you heard this customer was rude to ${rudeAt.first} earlier today. '
        'Tease them about it a little.',
      );
    }
    return parts.join(' ');
  }

  /// The ready-made greeting's opener when a friend came by (simple mode, or when the AI didn't answer).
  String? _gossipOpener(String stallId) {
    final f = (gossip[stallId] ?? const []).firstOrNull;
    final name = f == null ? '' : (cleanName('${f['name']}') ?? '').replaceAll(RegExp(r'\d+'), '').trim();
    return name.isEmpty ? null : 'Eh, your friend $name came by also!';
  }

  // ---------------------------------------------------------------- your own stall (roles reversed)
  final _sales = <String, ({Sale sale, List<Map<String, Object?>> chat, int seed})>{};

  /// A customer comes to your stall. [productId]: what you sell (default: the next one in turn).
  Future<Map<String, Object?>> shopStart([String? productId]) async {
    final shop = (_profile['shop'] ??= <String, Object?>{}) as Map;
    final n = ((shop['served'] ?? 0) as num).toInt();
    // what you bought at the market is what you sell (the oldest first); with nothing in stock, wholesale goods
    final stock = progress.stock;
    final Product product;
    if (productId == null && stock.isNotEmpty) {
      final x = stock.first;
      product = Product(
        'stock:${x['key']}',
        '${x['name']}',
        '${x['emoji']}',
        (x['cost'] as num).toDouble(),
        (x['fair'] as num).toDouble(),
      );
    } else {
      product = products.firstWhere((p) => p.id == productId, orElse: () => products[n % products.length]);
    }
    final customer = customers[_rnd.nextInt(customers.length)];
    final seed = _rnd.nextInt(1 << 31);
    final sale = Sale(product, customer, seed: seed);
    if (progress.owns('awning')) sale.most = (sale.most * 1.05 * 2).round() / 2; // a nicer stall: they pay a bit more
    final id = 's${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}${_rnd.nextInt(1 << 20).toRadixString(36)}';
    _sales[id] = (sale: sale, chat: <Map<String, Object?>>[], seed: seed);
    return _shopSay(id, 'greet');
  }

  /// Your move: name a price, take their offer, or chat.
  Future<Map<String, Object?>> shopMove(String id, {double? ask, bool take = false, bool chat = false}) async {
    final s = _sales[id];
    if (s == null) throw GameError(404, 'That customer has gone home');
    if (s.sale.done) throw GameError(409, 'This sale is over');
    String event;
    if (take) {
      s.chat.add({'who': 'you', 'text': 'Okay, ${money2(s.sale.offer)}. Deal!'});
      event = s.sale.take();
    } else if (ask != null) {
      if (ask <= 0 || ask > 100000) throw GameError(400, 'Name a price in dollars.');
      s.chat.add({'who': 'you', 'text': '${money2((ask * 2).round() / 2)}, can?'});
      event = s.sale.askFor(ask);
    } else if (chat) {
      s.chat.add({
        'who': 'you',
        'text': const [
          'Good choice! Very nice one.',
          'For you, I throw in a free bag!',
          'You have good taste!',
        ][s.sale.chats % 3],
      });
      event = s.sale.chat();
    } else {
      throw GameError(400, 'Name a price, take their offer, or chat');
    }
    final out = await _shopSay(id, event);
    if (s.sale.done) {
      final shop = (_profile['shop'] ??= <String, Object?>{}) as Map;
      shop['served'] = ((shop['served'] ?? 0) as num).toInt() + 1;
      final notes = <String>[];
      if (s.sale.result == 'sold') {
        if (s.sale.product.id.startsWith('stock:')) {
          progress.takeStock(s.sale.product.id.substring(6), s.sale.product.cost);
        }
        shop['sales'] = ((shop['sales'] ?? 0) as num).toInt() + 1;
        if (s.sale.profit > 0) {
          progress.addToJar(s.sale.profit);
          notes.add('🫙 ${money2(s.sale.profit)} profit into your savings jar (${money2(progress.jar)} saved).');
        }
        shop['profit'] = ((shop['profit'] ?? 0) as num).toDouble() + s.sale.profit;
        final fresh = <String>{};
        if (s.sale.stars >= 2) progress.earn('shopkeeper', fresh);
        for (final st in fresh) {
          final d = stickerDefs.firstWhere((x) => x.$1 == st);
          notes.add('New sticker! ${d.$2} ${d.$3}');
        }
      }
      out['notes'] = notes;
      out['totals'] = {'sales': shop['sales'] ?? 0, 'profit': shop['profit'] ?? 0};
      await _save();
    }
    return out;
  }

  Future<Map<String, Object?>> _shopSay(String id, String event) async {
    final s = _sales[id]!;
    final sale = s.sale;
    String? said = await customerSay(ai, sale, event, s.chat);
    final aiLine = said != null;
    said ??= customerLine(sale, event, s.seed + s.chat.length);
    s.chat.add({'who': 'them', 'text': said, if (aiLine) 'ai': true});
    return {
      'id': id,
      'event': event,
      'line': said,
      'ai_line': aiLine,
      'customer': {'id': sale.customer.id, 'name': sale.customer.name, 'look': sale.customer.look},
      'product': {
        'id': sale.product.id,
        'name': sale.product.name,
        'emoji': sale.product.emoji,
        'cost': sale.product.cost,
        'fair': sale.product.fair,
        'from': _stockFrom(sale.product.id),
      },
      'stock': progress.stock.length,
      'offer': sale.offer,
      'ask': sale.ask,
      'suggestions': sale.done ? <double>[] : sale.suggestions(),
      'done': sale.done,
      'result': sale.result,
      'price': sale.price,
      'profit': sale.done && sale.result == 'sold' ? sale.profit : null,
      'stars': sale.stars,
    };
  }

  /// The festival week today, if any (never in tests that turn surprises off).
  Festival? get festivalWeek => surprises ? festivalOn(dayKey(now())) : null;

  /// How the last typed message in a haggle was read (for tests and the live check tool).
  Map? lastYou(String id) {
    final chat = _sessions[id]?.chat ?? const [];
    for (final m in chat.reversed) {
      if (m['who'] == 'you') return m;
    }
    return null;
  }

  /// "She misunderstood me": keep the last typed message, how it was read, and her reply, on the phone.
  Future<void> flag(String id) async {
    final ss = _sessions[id];
    if (ss == null) throw GameError(404, 'No such haggle');
    final chat = ss.chat;
    for (var i = chat.length - 1; i > 0; i--) {
      final you = chat[i - 1], them = chat[i];
      if (you['who'] == 'you' && them['who'] == 'them') {
        final list = (_profile['reports'] ??= <Object>[]) as List;
        list.add({
          'at': now().toIso8601String(),
          'stall': ss.stall['id'],
          'item': ss.item['id'],
          'you': you['text'],
          'read_as': you['move'],
          'reading': you['reading'] ?? '',
          'also': you['also'] ?? '',
          'reply': them['text'],
          'context': chat.sublist(math.max(0, i - 7), i - 1),
        });
        if (list.length > 100) list.removeRange(0, list.length - 100);
        await _save();
        return;
      }
    }
    throw GameError(400, 'Nothing to report yet');
  }

  /// The reports as plain text, to copy and send to the game's maker.
  String reportsText() {
    final b = StringBuffer('Hawker Haggle: "she misunderstood me" reports (${reports.length})\n');
    for (final r in reports) {
      b.writeln('\n${'${r['at']}'.substring(0, 16)} ${r['stall']}/${r['item']}');
      for (final m in (r['context'] as List? ?? const []).cast<Map>().skip(
        math.max(0, ((r['context'] as List?)?.length ?? 0) - 4),
      )) {
        b.writeln('  ${m['who'] == 'them' ? 'her' : 'you'}: ${m['text']}');
      }
      b.writeln('  YOU : ${r['you']}');
      b.writeln(
        '  READ: ${r['read_as']}${'${r['also']}'.isNotEmpty ? ' + ${r['also']}' : ''}  (${'${r['reading']}'.isEmpty ? 'word rules / fast path' : r['reading']})',
      );
      b.writeln('  HER : ${r['reply']}');
    }
    return b.toString();
  }
}
