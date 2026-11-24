/// Reading what the player typed without the AI: word rules, the fast path for plain offers, a bare yes.
/// Port of server/hh/ai.py (rules, heard_by_rules, fast_offer, plain_yes); see test/core_fixtures_test.dart.
library;

import 'py.dart';

const moves = [
  'offer', 'budget', 'plead', 'pity', 'flirt', 'compliment', 'competitor', 'bulk', 'regular', 'smalltalk', 'rude',
  'walk', 'accept', //
];
const alsoKinds = ['compliment', 'regular', 'pity', 'flirt', 'rude'];

/// How a typed message was read.
class Heard {
  const Heard(
    this.move,
    this.price, {
    this.ai = false,
    this.reading = '',
    this.unclear = '',
    this.also = '',
    this.relOp = '',
    this.relAmount,
    this.per = '',
    this.qty,
  });
  final String move; // one of [moves], or "clarify"
  final double? price;
  final bool ai; // the model read it
  final String reading; // what the model thinks they mean
  final String unclear; // for clarify: what to ask them
  final String also; // a second thing said in the same message
  final String relOp; // less / halfway / round_down
  final double? relAmount;
  final String per; // total / each
  final int? qty;

  Heard copyWith({String? move, double? price, bool clearPrice = false, String? unclear, String? per}) => Heard(
    move ?? this.move,
    clearPrice ? null : (price ?? this.price),
    ai: ai,
    reading: reading,
    unclear: unclear ?? this.unclear,
    also: also,
    relOp: relOp,
    relAmount: relAmount,
    per: per ?? this.per,
    qty: qty,
  );

  Map<String, Object?> toMap() => {
    'move': move,
    'price': price,
    'also': also,
    'rel_op': relOp,
    'rel_amount': relAmount,
    'per': per,
    'qty': qty,
  };
}

final _words = <(String, RegExp)>[
  ('walk', pyRe(r"\b(never ?mind|forget it|bye|no need|nvm|i think first|walk)\b")),
  ('competitor', pyRe(r"\b(next stall|other stall|another stall|cheaper (there|elsewhere)|shopee|lazada)\b")),
  ('bulk', pyRe(r"\b(two|2 pcs|buy more|buy 2|bulk|both)\b")),
  ('regular', pyRe(r"\b(every week|regular|always (buy|come)|remember me)\b")),
  ('rude', pyRe(r"\b(stupid|idiot|cheat|scam|rubbish|lousy)\b")),
  ('flirt', pyRe(r"\b(date|marry( me)?|girlfriend|boyfriend|sexy|kiss|i love you|love you|darling|be my)\b")),
  (
    'pity',
    pyRe(
      r"\b(starving|hungry|nothing to eat|no food|no money|broke|jobless|lost my job|retrenched|sick|"
      r"hospital|kesian|pity me|very poor|so poor)\b",
    ),
  ),
  ('plead', pyRe(r"\b(cheaper|discount|less|lower|best price|kurang|reduce|so ex|so expensive)\b")),
  ('compliment', pyRe(r"\b(nice|fresh|beautiful|pretty|best|good|sweet|shiok|handsome|lovely)\b")),
  ('accept', pyRe(r"\b(deal|i('ll| will)? (take|buy)( it| this| one| lah)?|pack (it|for me)|wrap (it|for me))\b")),
  ('clarify', pyRe(r"^\s*(ok+|okay|can|fine|hmm+|ya|yes|sure)\b")),
];

final _yes = pyRe(
  r"^\W*(ok+|okay|yes+|ya+|yah|yup|can|sure|deal|done|fine|confirm|boleh|shiok|steady)"
  r"(\W+(lah|la|leh|lor|ah|deal|can|ok|okay|boss|auntie|uncle|kak|adik|confirm|then|plus chop))*\W*$",
  ignoreCase: true,
);

/// A bare yes ("ok lah", "can can", "yes deal") with nothing else: answers "deal or not?".
bool plainYes(String text) => _yes.hasMatch(plainDigits(text).trim());

final _relative = <(String, RegExp)>[
  ('halfway', pyRe(r"\b(half ?way|half half|split the difference|meet (in the )?(middle|halfway))\b")),
  ('round_down', pyRe(r"\b(round (it )?down|remove the cents|no cents|cut the cents)\b")),
  (
    'less',
    pyRe(r"\$?\s*(\d+(?:\.\d{1,2})?)\s*(dollars?|bucks)?\s*(less|off|cheaper)\b|\bminus\s*\$?\s*(\d+(?:\.\d{1,2})?)"),
  ),
];
final _number = RegExp(r'^\d+(?:\.\d+)?$');

/// The word-rule reading of a message, with the same extras the AI gives (relative price, also, per piece).
Heard heardByRules(String text) {
  final t = plainDigits(text).toLowerCase();
  for (final (op, rx) in _relative) {
    final m = rx.firstMatch(t);
    if (m != null) {
      double? amount;
      for (var i = 1; i <= m.groupCount; i++) {
        final g = m.group(i);
        if (g != null && g.isNotEmpty && _number.hasMatch(g)) {
          amount = double.parse(g);
          break;
        }
      }
      return Heard('offer', null, relOp: op, relAmount: amount);
    }
  }
  final tot = pyRe(r"\b(2|two)\s*(for|=)\s*\$?\s*(\d+(?:\.\d{1,2})?)").firstMatch(t);
  if (tot != null) return Heard('bulk', double.parse(tot.group(3)!), per: 'total');
  final (move, price) = rules(text);
  var also = '';
  if (const ['offer', 'budget', 'plead', 'bulk'].contains(move)) {
    for (final (side, pattern) in _words) {
      if (alsoKinds.contains(side) && pattern.hasMatch(t)) {
        also = side;
        break;
      }
    }
  }
  return Heard(move, price, also: also);
}

final _fast = pyRe(
  r"^[^\w$]*(\$)?\s*(\d+(?:\.\d{1,2})?)\s*(dollars?|bucks)?"
  r"(\s*(can|lah|la|ok|okay|boleh|leh|ah|lor|pls|please|or not|can or not))*\W*$",
  ignoreCase: true,
);

/// A plain offer like "15", "$12 can?", "15 lah": no need for the AI to read it.
double? fastOffer(String text, double ask) {
  final m = _fast.firstMatch(plainDigits(text).trim());
  if (m == null) return null;
  final v = double.parse(m.group(2)!);
  if ((v <= 5 && m.group(1) == null) || v <= 0 || v > ask * 2) return null;
  return v;
}

final _budget = pyRe(
  r"\b(only (have|got|left)|budget|all i (have|got)|can only (pay|afford)|left)\b[^\d]{0,12}\$?\s*(\d+(?:\.\d{1,2})?)"
  r"|\$?\s*(\d+(?:\.\d{1,2})?)\s*(is|only)?\s*all i (have|got)",
);
final _qty = pyRe(r"\b(buy|take|want|give me|get)\s+(\d+)\b(?!\s*(dollars?|bucks|\$))");
final _anyNumber = RegExp(r'\d+(?:\.\d+)?');
final _for = pyRe(r"\bfor\b");
final _firstPrice = RegExp(r'\$?\s*(\d+(?:\.\d{1,2})?)');
final _negation = pyRe(r"\b(no|not|don'?t|won'?t|never|but|if)\b");

/// The simple word rules: (move, price).
(String, double?) rules(String text) {
  final t = plainDigits(text).toLowerCase();
  final bud = _budget.firstMatch(t);
  if (bud != null) return ('budget', double.parse(bud.group(5) ?? bud.group(6)!));
  final qty = _qty.firstMatch(t);
  if (qty != null && int.parse(qty.group(2)!) != 1) {
    return int.parse(qty.group(2)!) == 2 ? ('bulk', null) : ('clarify', null); // "I buy 100 for 150": ask
  }
  if (_anyNumber.allMatches(t).length > 1 && _for.hasMatch(t)) return ('clarify', null); // per piece or total?
  final m = _firstPrice.firstMatch(t);
  if (m != null && !pyRe('\\b(buy|take)\\s+${RegExp.escape(m.group(1)!)}\\b').hasMatch(t)) {
    return ('offer', double.parse(m.group(1)!));
  }
  for (final (move, pattern) in _words) {
    if (pattern.hasMatch(t)) {
      if (move == 'accept' && _negation.hasMatch(t)) return ('clarify', null); // "no deal", "I take it if..."
      return (move, null);
    }
  }
  return ('smalltalk', null);
}
