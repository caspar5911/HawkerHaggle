/// Helpers for the stallholder's lines: money, the price-safety check, mood and opener hints, the transcript.
/// Port of server/hh/ai.py; checked against test/fixtures/reference.json.
library;

import 'py.dart';

/// "$12", "$12.50" (like the Python money()).
String money(num? v) {
  if (v == null) return '';
  final d = v.toDouble();
  if (d != d.truncateToDouble()) return '\$${fixed2(d)}'.replaceAll('.00', '');
  return '\$${d.toInt()}';
}

final _percent = RegExp(r'percent|%|\bdiscount of\b', caseSensitive: false);
final _dollars = RegExp(r'\$\s*(\d+(?:\.\d+)?)');
final _free = pyRe(r"\bfree\b", ignoreCase: true);
final _units = pyRe(
  r"(?<![$\d.])\d+(?:\.\d+)?\s*(years?|yrs?|kg|kilos?|g|grams?|pieces?|pcs|days?|hours?|hrs?|"
  r"minutes?|mins?|am|pm|o'?clock|times?|generations?|months?|weeks?|cm|m|km|mah|w|watts?|"
  r"usb|ports?)\b",
  ignoreCase: true,
);
final _plainNumbers = RegExp(r'(?<![\d$.])(\d+(?:\.\d+)?)');

/// Keep a model reply only if it can't mislead about the price: every $ amount must be one of the game's prices,
/// other numbers must be game prices, small counts or things with units, and "free" only next to a real price.
final _thinkBlock = RegExp(r'<think>[\s\S]*?</think>', caseSensitive: false);
final _tag = RegExp(r'</?[a-z][^<>]*>', caseSensitive: false);

/// The model's private reasoning sometimes leaks into its answer (a draft, then a closing `think` tag, then the
/// real reply; or a whole `think` block): only what comes after the thinking is the answer. Thinking that never ends
/// is no answer at all.
String withoutThinking(String text) {
  var t = text.replaceAll(_thinkBlock, '');
  final close = t.toLowerCase().lastIndexOf('</think>');
  if (close >= 0) t = t.substring(close + '</think>'.length);
  final start = t.toLowerCase().indexOf('<think>');
  if (start >= 0) t = t.substring(0, start);
  return t.trim();
}

String? checked(String? text, Iterable<num> allowed, {Iterable<num> counts = const [], bool dollarCounts = false}) {
  if (text == null || text.isEmpty) return null;
  text = pySlice(firstLine(stripChars(text.trim(), '"')), 220);
  if (_tag.hasMatch(text)) return null; // a stray tag (<think>, </b>...) is never something she says
  final ok = {for (final a in allowed) pyRound(a.toDouble(), 2)};
  final dollars = {
    ...ok,
    if (dollarCounts)
      for (final c in counts) pyRound(c.toDouble(), 2),
  };
  if (_percent.hasMatch(text)) return null;
  final amounts = [for (final m in _dollars.allMatches(text)) pyRound(double.parse(m.group(1)!), 2)];
  if (amounts.any((a) => !dollars.contains(a))) return null;
  if (_free.hasMatch(text) && !amounts.any((a) => ok.contains(a) && a > 0)) return null;
  final plain = {...ok, for (final c in counts) pyRound(c.toDouble(), 2)};
  final noUnits = text.replaceAll(_units, ' ');
  for (final m in _plainNumbers.allMatches(noUnits)) {
    final v = pyRound(double.parse(m.group(1)!), 2);
    if (!plain.contains(v) && v > 3) return null;
  }
  return text.isEmpty ? null : text;
}

const endings = ['accept', 'confirm', 'letgo', 'refuse', 'greet', 'callback'];

/// How she feels right now, so the tone follows the game (and warns the player before she gives up).
String moodLine(String event, double? patience, String also) {
  final parts = <String>[];
  if (patience != null && !endings.contains(event)) {
    if (patience < 25) {
      parts.add('Your patience is almost gone: say clearly this is their last chance to decide.');
    } else if (patience < 50) {
      parts.add("You're getting impatient: tell them, nicely, to decide soon.");
    } else if (patience >= 85) {
      parts.add("You're relaxed and in a good mood.");
    }
  }
  final hint = const {
    'compliment': 'They also complimented you: enjoy it a little.',
    'regular': "They also said they're a regular: be a bit warmer.",
    'pity': 'They also told you something sad: show a little sympathy.',
    'flirt': "They also flirted: laugh it off, firmly don't flirt back.",
    'rude': "They were also rude: show you're a bit offended.",
  }[also];
  if (hint != null) parts.add(hint);
  return parts.join(' ');
}

final _word = RegExp(r"[A-Za-z']+");

/// Her recent first words, so she doesn't start every line with "Aiyo".
String openerHint(List<Map> history) {
  final firsts = <String>[];
  final recent = history.length > 8 ? history.sublist(history.length - 8) : history;
  for (final m in recent) {
    if (m['who'] == 'them') {
      final w = _word.firstMatch('${m['text'] ?? ''}');
      if (w != null) firsts.add(capitalize(w[0]!));
    }
  }
  final seen = firsts.toSet().toList()..sort();
  return seen.isEmpty ? '' : "Start differently from your recent lines (don't open with: ${seen.join(', ')}).";
}

String transcript(List<Map> history, String name, {int limit = 10}) {
  final recent = history.length > limit ? history.sublist(history.length - limit) : history;
  final lines = [
    for (final m in recent) '${m['who'] == 'them' ? name : 'Customer'}: ${pySlice('${m['text'] ?? ''}', 200)}',
  ];
  return lines.isEmpty ? '(nothing yet)' : lines.join('\n');
}
