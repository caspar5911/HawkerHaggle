// A month of things to do: daily challenges, weekly quests, rank, Market Month, unlocks over time.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hawker_haggle/core/challenges.dart';
import 'package:hawker_haggle/core/game.dart';

final content = jsonDecode(File('assets/content/stalls.json').readAsStringSync()) as Map<String, dynamic>;

class Clock {
  Clock([DateTime? t]) : t = t ?? DateTime(2026, 11, 24, 10);
  DateTime t;
  DateTime call() => t;
  void nextDay([int n = 1]) => t = DateTime(t.year, t.month, t.day + n, 10);
}

Future<(Game, Clock)> newGame({DateTime? at, bool unlockAll = false}) async {
  final clock = Clock(at);
  final g = Game(content: content, store: MemoryKeyValue(), now: clock.call, unlockAll: unlockAll, surprises: false);
  await g.load();
  return (g, clock);
}

Future<Map> buy(Game g, String stall, String item, {String surprise = 'none', List<String> say = const []}) async {
  var r = await g.start(stall, item, surprise);
  final id = r['id'] as String;
  for (final t in say) {
    r = await g.move(id, text: t);
    if (r['done'] == true) return r;
  }
  return r['pending'] != null ? g.move(id, move: 'confirm') : g.move(id, move: 'buy');
}

/// Her real lowest price via a firm budget, then yes: 3 stars, 30%+ off.
Future<Map> bargain(Game g, String stall, String item, {String surprise = 'none'}) async {
  final it = ((content['stalls'] as List).firstWhere((s) => s['id'] == stall)['items'] as List).firstWhere(
    (i) => i['id'] == item,
  );
  final r = await g.start(stall, item, surprise);
  final id = r['id'] as String;
  var x = await g.move(id, text: 'I only have \$${((it['floor'] as num) * 0.8).floor()}');
  x = await g.move(id, text: '\$${x['ask']} ok I take');
  return x['pending'] != null ? g.move(id, move: 'confirm') : x;
}

Future<void> playKind(Game g, Daily d, String st, String item) async {
  switch (d.id) {
    case 'deal_at' || 'stars2_item' || 'three_stars' || 'off30' || 'under_fair':
      await bargain(g, st, item);
    case 'patient' || 'quick':
      await buy(g, st, item);
    case 'typed_only':
      await buy(g, st, item, say: ['ok I take it', 'yes']);
    case 'buy_two':
      await buy(g, st, item, say: ['I take two, cheaper?']);
    case 'final_final':
      for (var i = 0; i < 60; i++) {
        final r = await g.start('raj', 'case', 'none');
        final id = r['id'] as String;
        await g.move(id, text: '12');
        final w = await g.move(id, move: 'walk');
        if (w['event'] == 'callback') {
          await g.move(id, move: 'buy');
          return;
        }
      }
    case 'beat_rose':
      await buy(g, st, item, surprise: 'rival');
    case 'rain_deal':
      await buy(g, st, item, surprise: 'rain');
    case 'closing_deal':
      await buy(g, st, item, surprise: 'closing');
    case 'festival_deal':
      await bargain(g, st, item, surprise: 'festival');
    case 'sweet_talk':
      await buy(g, st, item, say: ['wah so nice']);
    case 'regular':
      await buy(g, st, item, say: ['I come every week']);
    case 'competitor':
      await buy(g, st, item, say: ['next stall cheaper leh']);
    case 'budget':
      await bargain(g, st, item);
    case 'pity':
      await buy(g, st, item, say: ['no money lah']);
    case 'two_stalls':
      await buy(g, 'mei', 'mango');
      await buy(g, 'lim', 'pomfret');
    case 'three_deals' || 'polite':
      for (var i = 0; i < 3; i++) {
        await buy(g, st, item);
      }
    default:
      fail('no scripted way to play ${d.id}');
  }
}

void main() {
  test('the daily challenge is the same for everyone on a day, and changes from day to day', () async {
    final (a, ca) = await newGame();
    final (b, _) = await newGame();
    expect(a.challenges()['daily'], b.challenges()['daily']);
    final seen = <String>{};
    for (var d = 0; d < 60; d++) {
      seen.add('${(a.challenges()['daily'] as Map)['id']}');
      ca.nextDay();
    }
    expect(seen.length, greaterThanOrEqualTo(12));
  });

  test('every kind of daily challenge can be completed by playing', () async {
    final (probe, _) = await newGame();
    final kinds = Challenges(probe.progress).pool(5);
    expect(kinds.length, greaterThanOrEqualTo(20));
    for (final d in kinds) {
      final (g, _) = await newGame(unlockAll: true);
      final mine = Challenges(g.progress).pool(5).firstWhere((x) => x.id == d.id);
      final st = mine.stall.isEmpty ? 'mei' : mine.stall;
      final item = mine.id == 'stars2_item' || mine.id == 'under_fair'
          ? RegExp(r'on the (.*)\.$|Buy the (.*) at').firstMatch(mine.how) == null
                ? ((content['stalls'] as List).firstWhere((s) => s['id'] == st)['items'] as List).first['id'] as String
                : ((content['stalls'] as List).firstWhere((s) => s['id'] == st)['items'] as List).firstWhere(
                        (i) => mine.how.contains('${i['name']}'),
                      )['id']
                      as String
          : ((content['stalls'] as List).firstWhere((s) => s['id'] == st)['items'] as List).first['id'] as String;
      await playKind(g, mine, st, item);
      final todays = [for (final h in (g.progress.p['haggles'] as List).cast<Map>()) h];
      expect(mine.check(todays, todays.last), isTrue, reason: '${d.id} not completed');
    }
  });

  test('finishing the daily challenge gives XP once, and a note on the result card', () async {
    final (g, _) = await newGame(unlockAll: true);
    final d = Challenges(g.progress).daily();
    final st = d.stall.isEmpty ? 'mei' : d.stall;
    final items = ((content['stalls'] as List).firstWhere((s) => s['id'] == st)['items'] as List).cast<Map>();
    final item = items.firstWhere((i) => d.how.contains('${i['name']}'), orElse: () => items.first)['id'] as String;
    final before = g.progress.p['xp'] as int? ?? 0;
    await playKind(g, d, st, item);
    final c = g.challenges();
    expect((c['daily'] as Map)['done'], isTrue);
    expect((c['rank'] as Map)['xp'] as int, greaterThanOrEqualTo(before + xpDailyChallenge));
    await playKind(g, d, st, item);
    expect((g.progress.p['done_daily'] as Map).length, 1); // the daily reward is given once a day
  });

  test(
    'weekly quests: four a week, progress counts within the week, rolls over on Monday and across New Year',
    () async {
      final (g, clock) = await newGame(at: DateTime(2026, 12, 27, 10)); // a Sunday
      final q1 = g.challenges()['quests'] as List;
      expect(q1, hasLength(4));
      expect(g.challenges()['week_ends'], '2026-12-27');
      await buy(g, 'mei', 'mango');
      final deals = (g.challenges()['quests'] as List).cast<Map>().where((q) => q['id'] == 'deals');
      if (deals.isNotEmpty) expect(deals.first['have'], 1);
      clock.nextDay(); // Monday 28 Dec 2026: a new week (runs into 2027)
      expect(g.challenges()['week_ends'], '2027-01-03');
      expect((g.challenges()['quests'] as List).cast<Map>().every((q) => q['have'] == 0), isTrue);
      clock.nextDay(5); // Saturday 2 Jan 2027, same week
      await buy(g, 'lim', 'prawns');
      expect(g.challenges()['week_ends'], '2027-01-03');
      expect(weekStart(DateTime(2027, 1, 3)), DateTime(2026, 12, 28));
      expect(weekStart(DateTime(2027, 1, 4)), DateTime(2027, 1, 4));
    },
  );

  test('a month of play: a grinder cannot finish early; a casual player gets something new every few days', () async {
    // the grinder: 100 quick deals every day
    final (grinder, gc) = await newGame();
    var grinderMaxDay = 0;
    for (var day = 1; day <= 30; day++) {
      for (var i = 0; i < 100; i++) {
        await buy(grinder, ['mei', 'lim', 'raj', 'siti'][i % 4], ['mango', 'pomfret', 'case', 'kueh'][i % 4]);
      }
      if (grinderMaxDay == 0 && (grinder.challenges()['rank'] as Map)['max'] == true) grinderMaxDay = day;
      gc.nextDay();
    }
    expect(grinderMaxDay == 0 || grinderMaxDay >= 20, isTrue, reason: 'grinder hit the top rank on day $grinderMaxDay');

    // the casual player: Mum's list, today's challenge (attempted), one more haggle
    final (casual, cc) = await newGame();
    final newThings = <int>[];
    var casualMaxDay = 0;
    var lastRank = 1;
    var lastStickers = 0;
    for (var day = 1; day <= 30; day++) {
      final t = casual.today();
      for (final i in (t['items'] as List).cast<Map>()) {
        await bargain(casual, i['stall'] as String, i['item'] as String);
      }
      final d = Challenges(casual.progress).daily();
      final st = d.stall.isEmpty ? 'mei' : d.stall;
      final items = ((content['stalls'] as List).firstWhere((s) => s['id'] == st)['items'] as List).cast<Map>();
      final item = items.firstWhere((i) => d.how.contains('${i['name']}'), orElse: () => items.first)['id'] as String;
      if (d.id != 'final_final') await playKind(casual, d, st, item);
      final c = casual.challenges();
      final rank = (c['rank'] as Map)['level'] as int;
      if (casualMaxDay == 0 && (c['rank'] as Map)['max'] == true) casualMaxDay = day;
      final stickers = casual.stickers().where((s) => s['earned'] != null).length;
      final milestone = milestones.any((m) => m.$1 == day);
      if (rank > lastRank || stickers > lastStickers || milestone) newThings.add(day);
      lastRank = rank;
      lastStickers = stickers;
      // stalls open on schedule
      final open = {for (final s in (casual.stalls()['stalls'] as List).cast<Map>()) s['id']: s['locked'] != true};
      expect(open['wong'], day >= 7, reason: 'Uncle Wong on day $day');
      expect(open['kumar'], day >= 14, reason: 'Madam Kumar on day $day');
      cc.nextDay();
    }
    expect(casual.progress.daysPlayed(), 30);
    for (final id in ['days3', 'dailies7', 'week_done', 'month']) {
      expect(casual.stickers().firstWhere((s) => s['id'] == id)['earned'], isNotNull, reason: id);
    }
    // something new at least every 4 days
    var prev = 0;
    for (final d in [...newThings, 31]) {
      expect(d - prev, lessThanOrEqualTo(4), reason: 'nothing new between day $prev and day $d ($newThings)');
      prev = d;
    }
    final rank = casual.challenges()['rank'] as Map;
    // ignore: avoid_print
    print(
      'casual after 30 days: rank ${rank['level']} ${rank['title']} (${rank['xp']} XP), top rank on day '
      '$casualMaxDay; grinder top rank on day ${grinderMaxDay == 0 ? 'never' : grinderMaxDay}',
    );
    expect(casualMaxDay == 0 || casualMaxDay >= 26, isTrue, reason: 'casual hit the top rank on day $casualMaxDay');
    expect(rank['level'] as int, greaterThanOrEqualTo(10));
  });

  test('a test-17 profile gets days played and XP for its past haggles', () async {
    final store = MemoryKeyValue();
    await store.write(
      'profile',
      jsonEncode({
        'name': 'Shiok Otter 123',
        'haggles': [
          {'stall': 'mei', 'item': 'durian', 'result': 'deal', 'deal': 18, 'stars': 3, 'at': '2026-11-20T10:00:00'},
          {'stall': 'lim', 'item': 'pomfret', 'result': 'walked', 'stars': 0, 'at': '2026-11-21T10:00:00'},
        ],
        'reports': [],
        'friends': {},
        'stickers': {},
      }),
    );
    final g = Game(content: content, store: store);
    await g.load();
    expect(g.progress.daysPlayed(), 2);
    expect((g.challenges()['rank'] as Map)['xp'], 2 * xpDayPlayed + 14 + 2);
    await g.deleteAll();
    expect(g.progress.daysPlayed(), 0);
    expect((g.challenges()['rank'] as Map)['xp'], 0);
  });
}
