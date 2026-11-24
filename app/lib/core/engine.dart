/// The haggling engine: plain code that owns every number. The AI never decides prices.
/// Port of server/hh/engine.py; checked move by move against test/fixtures/reference.json.
library;

import 'dart:math' as math;

import 'py.dart';

const engineMoves = [
  'offer', 'budget', 'plead', 'pity', 'flirt', 'compliment', 'competitor', 'bulk', 'regular', 'smalltalk', 'rude',
  'walk', 'accept', //
];
const once = ['competitor', 'bulk', 'regular']; // tactics that only work once per haggle
const maxRounds = 12;

class Personality {
  const Personality({
    required this.stubborn,
    required this.flattery,
    required this.temper,
    required this.callback,
    this.kind = 0.5,
  });
  factory Personality.fromJson(Map m) => Personality(
    stubborn: (m['stubborn'] as num).toDouble(),
    flattery: (m['flattery'] as num).toDouble(),
    temper: (m['temper'] as num).toDouble(),
    callback: (m['callback'] as num).toDouble(),
    kind: ((m['kind'] ?? 0.5) as num).toDouble(),
  );
  final double stubborn, flattery, temper, callback, kind;
}

class Item {
  const Item({required this.id, required this.name, required this.fair, required this.ask, required this.floor});
  factory Item.fromJson(Map m) => Item(
    id: m['id'] as String,
    name: m['name'] as String,
    fair: (m['fair'] as num).toDouble(),
    ask: (m['ask'] as num).toDouble(),
    floor: (m['floor'] as num).toDouble(),
  );
  final String id, name;
  final double fair, ask, floor; // floor: the secret lowest price
}

class HaggleState {
  HaggleState({required this.ask, required this.opening});
  double ask;
  double opening;
  double patience = 100;
  double mood = 0; // -3 .. +3
  int rounds = 0;
  int qty = 1;
  List<String> used = [];
  int compliments = 0, pleads = 0, pities = 0;
  double? budget; // "I only have $16"
  bool bestGiven = false; // they already said their real lowest price
  double? lastOffer;
  bool done = false;
  String result = ''; // deal / walked / refused
  double? deal;
  double? pending; // agreed, waiting for the player's yes

  Map<String, Object?> toJson() => {
    'ask': ask, 'opening': opening, 'patience': patience, 'mood': mood, 'rounds': rounds, 'qty': qty, 'used': used,
    'compliments': compliments, 'pleads': pleads, 'pities': pities, 'budget': budget, 'best_given': bestGiven,
    'last_offer': lastOffer, 'done': done, 'result': result, 'deal': deal, 'pending': pending, //
  };
}

class Outcome {
  Outcome(this.event, this.ask, this.done, this.result, this.deal, this.offer, this.stars, this.saved, this.pending);
  final String event;
  final double ask;
  final bool done;
  final String result;
  final double? deal, offer;
  final int stars;
  final double saved; // fraction below the opening price
  final double? pending;

  Map<String, Object?> toJson() => {
    'event': event, 'ask': ask, 'done': done, 'result': result, 'deal': deal, 'offer': offer, 'stars': stars,
    'saved': saved, 'pending': pending, //
  };
}

/// Prices people actually say: 50-cent steps under $20, whole dollars above.
double nice(double price) {
  final step = price < 20 ? 0.5 : 1.0;
  return pyRound(roundHalfEven(price / step) * step, 2);
}

/// The nearest price people say that is not below [price].
double niceUp(double price) {
  final step = price < 20 ? 0.5 : 1.0;
  return pyRound((pyRound(price / step, 6)).ceilToDouble() * step, 2);
}

double clamp(double x, double lo, double hi) => math.max(lo, math.min(hi, x));

class Haggle {
  Haggle(this.item, this.p, {int seed = 0, HaggleState? state})
    : rng = math.Random(seed),
      s = state ?? HaggleState(ask: item.ask, opening: item.ask);
  final Item item;
  final Personality p;
  final math.Random rng;
  final HaggleState s;

  double floorNow() {
    final f = item.floor * (1 - 0.02 * s.mood) * (s.qty > 1 ? 0.95 : 1.0);
    return math.max(f, item.floor * 0.9);
  }

  void _tire(double amount) => s.patience -= amount * (0.5 + p.temper);

  void _concede(double toward, double share) {
    if (s.bestGiven) return; // their real best price stays their best price
    final f = floorNow();
    final target = math.max(toward, f);
    final n = nice(s.ask - (s.ask - target) * clamp(share, 0, 1));
    s.ask = n < s.ask ? math.max(n, nice(f)) : s.ask;
  }

  void _finish(String result, [double? deal]) {
    s.done = true;
    s.result = result;
    s.deal = deal;
  }

  int stars() {
    if (s.result != 'deal' || s.deal == null) return 0;
    if (s.deal! <= item.floor * 1.06) return 3;
    return s.deal! <= item.fair ? 2 : 1;
  }

  Outcome _out(String event, [double? offer]) {
    final saved = (s.deal != null && s.deal != 0) ? 1 - s.deal! / s.opening : 0.0;
    return Outcome(event, s.ask, s.done, s.result, s.deal, offer, stars(), pyRound(saved, 3), s.pending);
  }

  Outcome _agree(double price, [double? offer]) {
    s.pending = price;
    return _out('confirm', offer);
  }

  Outcome move(String kind, [double? price]) {
    if (s.done) return _out('over');
    if (kind == 'buy') {
      // The app's "OK lah, $X" button after its own "Confirm $X" tap: already confirmed.
      final deal = s.pending ?? s.ask;
      s.pending = null;
      _finish('deal', deal);
      return _out('accept', deal);
    }
    if (s.pending != null &&
        (kind == 'accept' ||
            ((kind == 'offer' || kind == 'budget') && price != null && price.isFinite && nice(price) >= s.pending!))) {
      kind = 'confirm'; // "OK lah" or the agreed price again, while a deal waits: that's a yes
    }
    if (kind == 'confirm') {
      if (s.pending == null) {
        kind = 'smalltalk';
      } else {
        final deal = s.pending!;
        s.pending = null;
        _finish('deal', deal);
        return _out('accept', deal);
      }
    }
    if (kind == 'cancel') {
      if (s.pending == null) {
        kind = 'smalltalk';
      } else {
        s.ask = math.min(s.ask, s.pending!);
        s.pending = null;
        _tire(6);
        if (s.patience <= 0) {
          _finish('refused');
          return _out('refuse');
        }
        return _out('unsure');
      }
    }
    if (s.pending != null) {
      s.ask = math.min(s.ask, s.pending!); // still bargaining
      s.pending = null;
    }
    if (!engineMoves.contains(kind)) kind = 'smalltalk';
    if (once.contains(kind) && s.used.contains(kind)) kind = price != null ? 'offer' : 'smalltalk';
    s.rounds += 1;
    final out = switch (kind) {
      'offer' => _offer(price),
      'budget' => _budget(price),
      'bulk' => _bulk(price),
      'plead' => _plead(),
      'pity' => _pity(),
      'flirt' => _flirt(),
      'compliment' => _compliment(),
      'competitor' => _competitor(),
      'regular' => _regular(),
      'rude' => _rude(),
      'walk' => _walk(),
      'accept' => _accept(),
      _ => _smalltalk(),
    };
    if (out.event == 'confirm') return out; // a deal on the table always gets its confirmation step
    if (!s.done && s.patience <= 0) {
      _finish('refused');
      return _out('refuse');
    }
    if (!s.done && s.rounds >= maxRounds) {
      _finish('refused');
      return _out('refuse');
    }
    return out;
  }

  Outcome _budget(double? price) {
    if (price != null && price.isFinite && price > 0) s.budget = nice(price);
    return _offer(price, firm: true);
  }

  Outcome _offer(double? price, {bool firm = false}) {
    if (price == null || !price.isFinite || price <= 0) {
      _tire(6);
      return _out('confused');
    }
    final x = nice(price);
    firm = firm || x == s.lastOffer; // saying the same number again means it
    s.lastOffer = x;
    final f = floorNow();
    if (x >= s.ask) return _agree(s.ask, x);
    final give = (item.ask - item.floor) * clamp(0.25 + 0.06 * s.mood - 0.15 * p.stubborn, 0.05, 0.5);
    if (s.bestGiven && x < s.ask) {
      _tire(9);
      return _out('final', x);
    }
    if (x >= f && (firm || x >= s.ask - give)) return _agree(x, x);
    if (x < f * 0.7) {
      _tire(22);
      s.mood = clamp(s.mood - 1, -3, 3);
      return _out('insulted', x);
    }
    if (firm) {
      _tire(9);
      if (!s.bestGiven) {
        s.bestGiven = true;
        final best = niceUp(f); // honest: this really is the lowest they'll go
        if (best < s.ask) {
          s.ask = best;
          return _out('budget_best', x);
        }
      }
      return _out('final', x);
    }
    final before = s.ask;
    _concede(x, 0.25 + 0.08 * s.mood - 0.15 * p.stubborn);
    _tire(7);
    return _out(s.ask >= before ? 'final' : 'counter', x);
  }

  Outcome _pity() {
    s.pities += 1;
    if (s.pities > 1) {
      _tire(8 + 10 * (1 - p.kind));
      return _out('pity_tired');
    }
    s.mood = clamp(s.mood + 2 * p.kind, -3, 3);
    _concede(floorNow(), 0.35 * p.kind);
    _tire(3);
    return _out('pity');
  }

  Outcome _compliment() {
    s.compliments += 1;
    if (s.compliments > 2) {
      _tire(12);
      return _out('flattery_tired');
    }
    s.mood = clamp(s.mood + 1.5 * p.flattery, -3, 3);
    _concede(floorNow(), 0.12 * p.flattery);
    _tire(3);
    return _out('flattered');
  }

  Outcome _plead() {
    s.pleads += 1;
    if (s.pleads > 2) {
      _tire(10);
      return _out('plead_no');
    }
    final before = s.ask;
    _concede(floorNow(), (s.pleads == 1 ? 0.18 : 0.1) * (1.1 - p.stubborn));
    _tire(6);
    return _out(s.ask < before ? 'plead' : 'plead_no');
  }

  Outcome _competitor() {
    s.used.add('competitor');
    if (rng.nextDouble() > p.stubborn) {
      _concede(floorNow(), 0.3);
      _tire(5);
      return _out('competitor_drop');
    }
    s.mood = clamp(s.mood - 0.5, -3, 3);
    _tire(14);
    return _out('competitor_annoyed');
  }

  Outcome _bulk(double? price) {
    s.used.add('bulk');
    s.qty = 2;
    _concede(floorNow(), 0.35 * (1.2 - p.stubborn));
    _tire(4);
    if (price != null) return _offer(price); // "2 for $40": $20 each
    return _out('bulk');
  }

  Outcome _flirt() {
    s.mood = clamp(s.mood - 0.5, -3, 3);
    _tire(8);
    return _out('deflect');
  }

  /// The mood part of a second thing said in the same message ("so nice, 20 can?"), within the usual limits.
  void side(String kind) {
    if (s.done) return;
    if (kind == 'compliment' && s.compliments < 2) {
      s.compliments += 1;
      s.mood = clamp(s.mood + 1.0 * p.flattery, -3, 3);
    } else if (kind == 'regular' && !s.used.contains('regular')) {
      s.used.add('regular');
      s.mood = clamp(s.mood + 0.7, -3, 3);
    } else if (kind == 'pity' && s.pities < 1) {
      s.pities += 1;
      s.mood = clamp(s.mood + 1.5 * p.kind, -3, 3);
    } else if (kind == 'flirt') {
      s.mood = clamp(s.mood - 0.5, -3, 3);
      _tire(4);
    } else if (kind == 'rude') {
      s.mood = clamp(s.mood - 1, -3, 3);
      _tire(12);
    }
  }

  Outcome _regular() {
    s.used.add('regular');
    s.mood = clamp(s.mood + 1, -3, 3);
    _concede(floorNow(), 0.1);
    _tire(4);
    return _out('regular');
  }

  Outcome _smalltalk() {
    s.mood = clamp(s.mood + 0.3, -3, 3);
    _tire(5);
    return _out('smalltalk');
  }

  Outcome _rude() {
    s.mood = clamp(s.mood - 2, -3, 3);
    _tire(30);
    return _out('rude');
  }

  Outcome _walk() {
    final f = floorNow();
    final room = s.ask - f;
    if (!s.bestGiven && room > f * 0.04 && rng.nextDouble() < p.callback * (0.6 + 0.15 * s.mood)) {
      s.ask = math.max(nice((s.ask + f) / 2), nice(f));
      _tire(10);
      return _out('callback');
    }
    _finish('walked');
    return _out('letgo');
  }

  Outcome _accept() => _agree(s.ask, s.ask);

  /// Three moves for tap mode: two offers (bold, safer) and one tactic. Never reveals the secret floor.
  List<Map<String, Object?>> suggestions() {
    if (s.done || s.pending != null) return [];
    final a = s.ask;
    final bold = nice(a * 0.6);
    var safer = nice(a * 0.82);
    if (safer >= a) safer = nice(a - (a < 20 ? 0.5 : 1));
    final tactics = [
      for (final m in const ['compliment', 'competitor', 'bulk', 'regular'])
        if (!s.used.contains(m) && !(m == 'compliment' && s.compliments >= 2)) m,
    ];
    return [
      {'move': 'offer', 'price': bold},
      {'move': 'offer', 'price': safer},
      {'move': tactics.isEmpty ? 'smalltalk' : tactics[rng.nextInt(tactics.length)], 'price': null},
    ];
  }
}
