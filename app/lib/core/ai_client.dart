/// Talks to any OpenAI-compatible chat endpoint (your own GLM, Ollama, LM Studio, OpenAI, OpenRouter...).
/// Two jobs: read what the player typed (understand) and write the stallholder's line (say). The game decides
/// every price; every line is checked before it's shown. Pure Dart, so it also runs from `dart run`.
library;

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'prompts.dart';
import 'prompts_extra.dart';
import 'py.dart';
import 'reader.dart';
import 'voice.dart';

/// She mustn't call a price final on these moments: she can still come down.
const notFinal = [
  'counter',
  'plead',
  'flattered',
  'regular',
  'competitor_drop',
  'pity',
  'bulk',
  'only_one',
  'back_to_one',
  'same_offer', //
  'smalltalk', 'unsure', 'clarify', //
];
final finalWords = pyRe(
  r"\b(final|last price|lowest|rock bottom|cannot go lower|can't go lower|cannot lower|no lower)\b",
  ignoreCase: true,
);

/// A reply that mentions prices must include her real one (asking price, or the agreed/sold price). Otherwise
/// "OK lah, $16" can repeat the customer's offer as if it were hers while the real price is $16.50.
bool ownPriceMissing(String text, Map<String, double?> numbers) {
  final amounts = {for (final m in RegExp(r'\$\s*(\d+(?:\.\d+)?)').allMatches(text)) pyRound(double.parse(m[1]!), 2)};
  final own = {
    for (final k in const ['ask', 'deal'])
      if (numbers[k] != null) pyRound(numbers[k]!, 2),
  };
  return amounts.isNotEmpty && own.isNotEmpty && amounts.intersection(own).isEmpty;
}

class AiConfig {
  const AiConfig({this.endpoint = '', this.model = '', this.apiKey = ''});
  final String endpoint; // e.g. https://host/v1
  final String model; // e.g. gx10-current, gpt-4o-mini, llama3.1
  final String apiKey; // optional

  bool get enabled => endpoint.trim().isNotEmpty;

  Uri get chatUri {
    var u = endpoint.trim().replaceAll(RegExp(r'/+$'), '');
    if (!u.endsWith('/chat/completions')) u = '$u/chat/completions';
    return Uri.parse(u);
  }
}

class AiClient {
  AiClient(this.config, {http.Client? client, this.timeout = const Duration(seconds: 30), this.log})
    : _http = client ?? http.Client();
  final AiConfig config;
  final http.Client _http;
  final Duration timeout;
  final void Function(String)? log;

  // What this endpoint accepts, learned on the first 400 (some reject reasoning_effort / response_format).
  bool _effort = true, _jsonMode = true;
  int _busy = 0;
  static const _slots = 2; // never more than 2 calls at once from this phone

  bool get enabled => config.enabled;

  Future<String?> chat(
    String system,
    String user, {
    bool json = false,
    double temperature = 0.7,
    String effort = 'low',
  }) async {
    if (!enabled) return null;
    final waitUntil = DateTime.now().add(const Duration(seconds: 2));
    while (_busy >= _slots) {
      if (DateTime.now().isAfter(waitUntil)) return null; // busy: use the plain-code fallback
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    _busy++;
    try {
      for (var attempt = 0; attempt < 2; attempt++) {
        final body = <String, Object?>{
          if (config.model.trim().isNotEmpty) 'model': config.model.trim(),
          'messages': [
            {'role': 'system', 'content': system},
            {'role': 'user', 'content': user},
          ],
          'temperature': json ? 0.1 : temperature,
          'max_tokens': 1200,
          if (_effort) 'reasoning_effort': effort,
          if (json && _jsonMode) 'response_format': {'type': 'json_object'},
        };
        final r = await _http
            .post(
              config.chatUri,
              headers: {
                'Content-Type': 'application/json',
                if (config.apiKey.trim().isNotEmpty) 'Authorization': 'Bearer ${config.apiKey.trim()}',
              },
              body: jsonEncode(body),
            )
            .timeout(timeout);
        if ((r.statusCode == 400 || r.statusCode == 422) && attempt == 0 && (_effort || _jsonMode)) {
          _effort = false; // retry once without the optional extras, and remember
          _jsonMode = false;
          log?.call('endpoint rejected optional parameters; retrying without them');
          continue;
        }
        if (r.statusCode >= 400) {
          log?.call('AI call failed: HTTP ${r.statusCode}');
          return null;
        }
        final data = jsonDecode(utf8.decode(r.bodyBytes)) as Map;
        final msg = ((data['choices'] as List).first as Map)['message'] as Map;
        return ('${msg['content'] ?? ''}').trim();
      }
      return null;
    } catch (e) {
      log?.call('AI call failed: ${e.runtimeType}');
      return null;
    } finally {
      _busy--;
    }
  }

  /// Settings > Test connection: one tiny call, with a readable result.
  Future<String> testConnection() async {
    final t = DateTime.now();
    final got = await chat('Answer with ONE JSON object only.', 'Say {"ok": true}', json: true);
    final ms = DateTime.now().difference(t).inMilliseconds;
    if (got == null) return "Couldn't reach the AI. Check the address, model name and key.";
    final ok = _jsonObject(got)?['ok'] == true;
    return ok
        ? 'Connected (${(ms / 1000).toStringAsFixed(1)}s${_jsonMode ? '' : ', simple mode for this endpoint'}).'
        : 'Connected, but the reply was unexpected. The game will still work, with simpler reading.';
  }

  /// What a typed message means as a move. Falls back to word rules when the model is busy or down.
  Future<Heard> understand(
    String text, {
    List<Map> history = const [],
    double? ask,
    String item = '',
    String name = 'Stallholder',
    double? pending,
    double? lastOffer,
    int qty = 1,
  }) async {
    final ctx = StringBuffer()
      ..write(
        'Item: ${item.isEmpty ? 'goods' : item}. The stallholder\'s current price: ${ask != null ? money(ask) : 'unknown'}.\n',
      )
      ..write(lastOffer != null ? "The customer's last offer was ${money(lastOffer)}.\n" : '')
      ..write(
        qty > 1
            ? "They are buying TWO; the stallholder's prices are per piece. If their number looks like the total for both, set per to total.\n"
            : '',
      )
      ..write(
        pending != null
            ? 'The stallholder has just AGREED to sell at ${money(pending)} and asked the customer to confirm.\n'
            : '',
      )
      ..write('Conversation so far:\n${transcript(history, name)}\n\n')
      ..write('Customer\'s NEW message: <<<${pySlice(text, 300)}>>>');
    final raw = await chat(understandPrompt, ctx.toString(), json: true, effort: 'medium');
    final data = raw == null ? null : _jsonObject(raw);
    if (data != null) {
      final move = '${data['move'] ?? ''}'.toLowerCase().trim();
      if (moves.contains(move) || move == 'clarify') {
        final price = _num(data['price']);
        final also = '${data['also'] ?? ''}'.toLowerCase().trim();
        final rel = data['relative'] is Map ? data['relative'] as Map : const {};
        final op = '${rel['op'] ?? ''}'.toLowerCase().trim();
        final per = '${data['per'] ?? ''}'.toLowerCase().trim();
        final qtyN = _num(data['qty'])?.toInt();
        return Heard(
          move,
          price != null && price > 0 ? price : null,
          ai: true,
          reading: pySlice('${data['reading'] ?? ''}', 200),
          unclear: pySlice('${data['unclear'] ?? ''}', 120),
          also: alsoKinds.contains(also) && also != move ? also : '',
          relOp: const ['less', 'percent', 'halfway', 'round_down'].contains(op) ? op : '',
          relAmount: _num(rel['amount']),
          per: const ['total', 'each'].contains(per) ? per : '',
          qty: qtyN != null && qtyN > 0 && qtyN < 1000 ? qtyN : null,
        );
      }
    }
    return heardByRules(text);
  }

  /// Walking away: is this the right moment to call them back with a final-final price? Null when busy or unsure.
  Future<bool?> callBack({
    required Map stall,
    required Map item,
    List<Map> history = const [],
    required double ask,
    double? lastOffer,
  }) async {
    final often = (((stall['personality'] as Map?)?['callback'] ?? 0.5) as num).toDouble();
    final system = callbackPrompt
        .replaceAll('{name}', '${stall['name']}')
        .replaceAll('{persona}', '${stall['persona']}')
        .replaceAll('{stall}', '${stall['stall']}'.toLowerCase())
        .replaceAll('{item}', '${item['name']}')
        .replaceAll('{often}', often >= 0.7 ? 'often' : (often >= 0.4 ? 'sometimes' : 'rarely'));
    final user =
        'Your price now: ${money(ask)}.${lastOffer != null ? ' Their last offer: ${money(lastOffer)}.' : ''}'
        '\nConversation:\n${transcript(history, '${stall['name']}', limit: 14)}';
    final raw = await chat(system, user, json: true, temperature: 0.3);
    final v = raw == null ? null : _jsonObject(raw)?['call_back'];
    return v is bool ? v : null;
  }

  /// Persuasion moments: score the customer's pitch 0..2 (null: no AI answer). Malformed answers count as 0.
  Future<int?> judgePitch({required Map stall, required Map item, required String pitch}) async {
    final system = pitchPrompt
        .replaceAll('{name}', '${stall['name']}')
        .replaceAll('{persona}', '${stall['persona']}')
        .replaceAll('{item}', '${item['name']}');
    final raw = await chat(system, '<<<${pySlice(pitch, 300)}>>>', json: true, temperature: 0.2);
    if (raw == null) return null;
    final v = _jsonObject(raw)?['score'];
    return v is num ? v.round().clamp(0, 2) : 0;
  }

  /// The stallholder's line, or null (use a ready-made line) if the model is unavailable or keeps breaking rules.
  Future<String?> say({
    required Map stall,
    required Map item,
    required String event,
    required Map<String, double?> numbers,
    List<Map> history = const [],
    String? heard,
    Iterable<num> alsoOk = const [],
    String unclear = '',
    double? budget,
    double? patience,
    String also = '',
    String note = '',
  }) async {
    final prices = {
      for (final e in numbers.entries)
        if (e.value != null) e.key: e.value!,
    };
    const noPriceOk = [
      'rude',
      'letgo',
      'refuse',
      'confused',
      'flattery_tired',
      'plead_no',
      'clarify',
      'unsure',
      'deflect',
      'rival_bought',
    ];
    if (prices.isEmpty && !noPriceOk.contains(event)) return null;
    final facts = [
      ...(stall['facts'] as List? ?? const []),
      ...(item['facts'] as List? ?? const []),
    ].map((f) => '$f').toList();
    final lines = stall['lines'] as Map;
    final samples = [
      for (final k in const ['greet', 'counter', 'smalltalk'])
        if (lines[k] is List && (lines[k] as List).isNotEmpty) '${(lines[k] as List).first}',
    ].join(' / ');
    final maxWords = ((stall['max_words'] ?? 30) as num).toInt();
    var brief = events[event] ?? extraEvents[event] ?? '';
    brief = brief.replaceAll('{unclear}', unclear.isEmpty ? 'what they mean' : unclear);
    for (final e in numbers.entries) {
      brief = brief.replaceAll('{${e.key}}', money(e.value));
    }
    final system = sayPrompt
        .replaceAll('{name}', '${stall['name']}')
        .replaceAll('{persona}', '${stall['persona']}')
        .replaceAll('{stall}', '${stall['stall']}'.toLowerCase())
        .replaceAll('{place}', '${stall['place']}'.split(',').first.toLowerCase())
        .replaceAll('{item}', '${item['name']}')
        .replaceAll('{voice}', '${stall['voice'] ?? ''}')
        .replaceAll('{max_words}', '$maxWords')
        .replaceAll(
          '{samples}',
          samples.replaceAll('{item}', '${item['name']}').replaceAll('{price}', r'$X').replaceAll('{offer}', r'$Y'),
        )
        .replaceAll('{facts}', facts.isEmpty ? '- (nothing special)' : facts.map((f) => '- $f').join('\n'))
        .replaceAll('{event}', brief)
        .replaceAll('{mood}', [moodLine(event, patience, also), note].where((x) => x.isNotEmpty).join(' '))
        .replaceAll('{openers}', openerHint(history))
        .replaceAll('{prices}', prices.isEmpty ? 'none' : prices.values.map(money).join(', '));
    var user =
        'Conversation so far:\n${transcript(history, '${stall['name']}')}\n\n'
        '${budget != null ? 'Remember: the customer said they only have ${money(budget)}.\n' : ''}'
        '${heard != null ? 'The customer just said: <<<${pySlice(heard, 300)}>>>\n' : ''}'
        'Your reply as ${stall['name']}:';
    // Plain numbers she may say: her facts ("6 mangoes", "20,000 mAh"), the item's own name ("tray of 30 eggs",
    // "12-layer kueh lapis") and, sometimes, the customer's own. Never as a price: $ amounts are only the game's.
    final factNumbers = [
      for (final m in RegExp(r'\d[\d,]*(?:\.\d+)?').allMatches([...facts, item['name'] ?? ''].join(' ')))
        double.parse(m[0]!.replaceAll(',', '')),
    ];
    final theirs = [for (final m in RegExp(r'\d+(?:\.\d+)?').allMatches(heard ?? '')) double.parse(m[0]!)];
    final repeatTheirs = const ['clarify', 'competitor_drop', 'competitor_annoyed'].contains(event) || note.isNotEmpty;
    final counts = [...factNumbers, if (repeatTheirs) ...theirs];
    final allowed = [...prices.values, ...alsoOk, ?budget];
    final nameLabel = RegExp(
      '^[^\\p{L}\\p{N}_]*${RegExp.escape('${stall['name']}')}[^\\p{L}\\p{N}_]*:\\s*',
      unicode: true,
    );
    for (var attempt = 0; attempt < 2; attempt++) {
      final raw = await chat(system, user, temperature: 0.9);
      if (raw == null) return null; // busy or down: use a ready-made line
      final text = raw.trim().replaceFirst(nameLabel, '');
      String? good = checked(text.replaceAll('20,000', '20000'), allowed, counts: counts, dollarCounts: repeatTheirs);
      good = good != null ? pySlice(firstLine(stripChars(text.trim(), '"')), 220) : null;
      var problem = 'a price or number you may not use';
      if (good != null && event == 'confirm' && !good.contains('?')) {
        good = null;
        problem = 'no question asking them to confirm';
      }
      if (good != null && event != 'clarify' && ownPriceMissing(good, numbers)) {
        good = null;
        problem =
            "a price that isn't yours: if you mention a price, say your real price "
            '${money(numbers['deal'] ?? numbers['ask'])}';
      }
      if (good != null && notFinal.contains(event) && finalWords.hasMatch(good)) {
        good = null;
        problem = 'a claim that your price is final, when you can still move';
      }
      if (good != null && pySplit(good).length > maxWords * 2) {
        good = null;
        problem = 'far too long (keep it under $maxWords words)';
      }
      if (good != null) return good;
      log?.call('AI line rejected ($event, try ${attempt + 1}, $problem)');
      user +=
          '\n\nYour last reply had $problem. Try again: the only \$ amounts you may write are '
          '${prices.isEmpty ? 'none' : prices.values.map(money).join(', ')}; no other prices, no percentages; '
          'under $maxWords words.';
    }
    return null;
  }

  void close() => _http.close();
}

/// Lenient JSON: strips code fences and takes the first {...} in the reply.
Map? _jsonObject(String raw) {
  var s = raw.trim();
  s = s.replaceFirst(RegExp(r'^```(?:json)?'), '').replaceFirst(RegExp(r'```$'), '').trim();
  final a = s.indexOf('{'), b = s.lastIndexOf('}');
  if (a < 0 || b <= a) return null;
  try {
    final v = jsonDecode(s.substring(a, b + 1));
    return v is Map ? v : null;
  } catch (_) {
    return null;
  }
}

double? _num(Object? v) {
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v.replaceAll(RegExp(r'[^\d.]'), ''));
  return null;
}
