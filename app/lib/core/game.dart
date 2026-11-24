/// The whole game, on the phone: haggles, reading messages, the stallholders' lines, stats and reports.
/// Port of server/hh/api.py. Returns the same shapes the server did, so the screens didn't change.
/// The only network use is the optional AI endpoint (see ai_client.dart).
library;

import 'dart:convert';
import 'dart:math' as math;

import 'ai_client.dart';
import 'engine.dart';
import 'challenges.dart';
import 'progress.dart';
import 'reader.dart';
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
  int nice = 0; // friendly moves (compliments, "I'm a regular"): a little extra friendship
  int typed = 0, tapped = 0; // how the player played (for challenges)
  final tactics = <String>{}; // compliment, regular, competitor, bulk, plead, pity, budget...
  bool rude = false;
  bool calledBack = false;
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

  // ---------------------------------------------------------------- profile (on the phone only)
  Future<void> load() async {
    final raw = await store.read('profile');
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

  Future<void> _save() => store.write('profile', jsonEncode(_profile));
  List<Map> get _done => [for (final h in (_profile['haggles'] as List? ?? const [])) h as Map];
  List<Map> get reports => [for (final r in (_profile['reports'] as List? ?? const [])) r as Map];

  Map<String, Object?> me() {
    final done = _done;
    return {
      'name': _profile['name'],
      'named': _profile['named'] == true,
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
    await store.delete('profile');
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
      'surprise_note': surpriseNote(h.s.event, '${ss.stall['name']}', h.s.rivalLeft),
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
    // About 1 haggle in 3 has a market surprise.
    if (!surprises) surprise ??= '';
    surprise ??= switch (_rnd.nextInt(100)) {
      < 9 => 'rain',
      < 18 => 'closing',
      < 26 => 'festival',
      < 34 => 'rival',
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
    _sessions[id] = ss;
    String? said;
    if (ai.enabled && (surprise.isNotEmpty || progress.hearts(stallId) > 0)) {
      // A friend, or a surprise: worth a fresh greeting from the AI.
      said = await ai.say(stall: stall, item: item, event: 'greet', numbers: {'ask': ss.h.s.ask}, note: _notes(ss));
    }
    final aiLine = said != null;
    said ??= _line(stall, item, surprise.isEmpty ? 'greet' : 'greet_$surprise', ss.h, seed: seed);
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
          heard.qty != null && heard.qty! > 2
              ? 'They asked for ${heard.qty}; you only have two left today, so say you can sell them two (prices are per piece).'
              : '',
        ),
      );
      aiLine = said != null;
    }
    said ??= _line(stall, item, event, h, offer: out?.offer, seed: ss.seed, chat: ss.chat);
    ss.chat.add({
      'who': 'you',
      'text': you,
      'move': kind,
      if (heard.reading.isNotEmpty || heard.also.isNotEmpty) ...{'reading': heard.reading, 'also': heard.also},
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
        },
        qty: h.s.qty,
        flags: {'nice': ss.nice, 'called_back': ss.calledBack, 'hard': hard},
        chat: ss.chat,
      );
      ss.finish = {'stickers': r.stickers, 'mum': r.mum, 'unlocked': r.unlocked, 'notes': r.notes};
      await _save();
    } else if (ss.rude) {
      await _save();
    }
    return _view(ss, said, event, out, you, aiLine);
  }

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
