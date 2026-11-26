/// ✨ Legendary items: on about one day in four, one stall has something rare, for that day only. It's the same stall
/// and item for everyone that day, so friends can talk about it. Harder to haggle for: less room between the asking
/// price and the lowest, and a stallholder in less of a mood to chat. Once bought, it's sold out until the next one.
///
/// Where a day's legendary item comes from, first match wins:
/// 1. an event the market's admin posted (from the server: no app update needed),
/// 2. a festival special, on two days of each festival week,
/// 3. the built-in rotation: each stall has three items, picked from the date.
///
/// The market server's board, Mum's list and the daily challenges never see these items.
library;

import 'festivals.dart';
import 'progress.dart' show dayKey, stableHash;

/// From this day the built-in rotation picks one of each stall's three items (before it, always the first, so the
/// days already announced stay as they were).
const rotationFrom = '2026-12-01';

const legendaryRotation = <String, List<Map<String, Object>>>{
  'mei': [
    {
      'id': 'legend_mei',
      'name': 'golden Musang King durian',
      'emoji': '🍈',
      'fair': 48,
      'ask': 68,
      'floor': 46,
      'facts': [
        'Picked from a 60-year-old tree in Raub, Pahang',
        'Only three of these this whole season',
        'Deep golden flesh, bitter-sweet and very creamy',
        'Sold whole, about 1.5 kg',
      ],
    },
    {
      'id': 'legend_mei_2',
      'name': 'box of Black Thorn durian',
      'emoji': '🍈',
      'fair': 70,
      'ask': 98,
      'floor': 66,
      'facts': [
        'Black Thorn from Penang, the rarest durian of the season',
        'Orange flesh, sweet first and a little bitter after',
        'About 1 kg of flesh, opened this morning',
      ],
    },
    {
      'id': 'legend_mei_3',
      'name': 'bunch of giant Shine Muscat grapes',
      'emoji': '🍇',
      'fair': 38,
      'ask': 55,
      'floor': 36,
      'facts': [
        'Grown in Okayama, Japan',
        'Each grape as big as a 50-cent coin, and seedless',
        'Crisp skin you can eat, honey-sweet',
      ],
    },
  ],
  'lim': [
    {
      'id': 'legend_lim',
      'name': 'giant wild red grouper',
      'emoji': '🐠',
      'fair': 55,
      'ask': 78,
      'floor': 52,
      'facts': [
        "Caught this morning off Pulau Ubin by Uncle Lim's old fishing friend",
        'About 2 kg, wild, not farmed',
        'Best steamed Hong Kong style with ginger and soy',
      ],
    },
    {
      'id': 'legend_lim_2',
      'name': 'giant Sri Lankan mud crab',
      'emoji': '🦀',
      'fair': 75,
      'ask': 108,
      'floor': 70,
      'facts': [
        'A huge mud crab, about 1.2 kg, still lively',
        'Perfect for chilli crab or black pepper crab',
        'Uncle Lim gets only two of these a month',
      ],
    },
    {
      'id': 'legend_lim_3',
      'name': 'wild-caught threadfin (ikan kurau)',
      'emoji': '🐟',
      'fair': 60,
      'ask': 85,
      'floor': 56,
      'facts': [
        'Wild ikan kurau, the best fish for Teochew fish porridge',
        'About 1.5 kg, caught last night',
        'Firm, sweet flesh',
      ],
    },
  ],
  'raj': [
    {
      'id': 'legend_raj',
      'name': 'limited-edition gold power bank',
      'emoji': '🔋',
      'fair': 50,
      'ask': 75,
      'floor': 48,
      'facts': [
        'Only 50 were made, and each one is numbered',
        'Fast-charges two phones at once',
        'Gold-coloured aluminium case, comes in a gift box',
      ],
    },
    {
      'id': 'legend_raj_2',
      'name': 'pair of noise-cancelling earbuds, sealed box',
      'emoji': '🎧',
      'fair': 90,
      'ask': 130,
      'floor': 85,
      'facts': [
        'Sealed in the box, with a one-year local warranty',
        'Noise cancelling, up to 8 hours on one charge',
        'Boss Raj got only five from his supplier',
      ],
    },
    {
      'id': 'legend_raj_3',
      'name': 'retro handheld game console',
      'emoji': '🎮',
      'fair': 40,
      'ask': 58,
      'floor': 37,
      'facts': ['500 classic-style games built in', 'Rechargeable, plays about 6 hours', 'Plugs into a TV too'],
    },
  ],
  'siti': [
    {
      'id': 'legend_siti',
      'name': 'hand-drawn silk batik scarf',
      'emoji': '🧣',
      'fair': 60,
      'ask': 88,
      'floor': 56,
      'facts': [
        "Hand-drawn with a canting by Kak Siti's mother in Pekalongan",
        'Pure silk; one scarf takes a month to make',
        'One of a kind: no two are the same',
      ],
    },
    {
      'id': 'legend_siti_2',
      'name': 'hand-beaded Nyonya kebaya',
      'emoji': '👚',
      'fair': 110,
      'ask': 160,
      'floor': 104,
      'facts': [
        "Embroidered and beaded by hand by Kak Siti's aunt",
        'Nyonya style, with a flower pattern',
        'Size M, and she can alter it',
      ],
    },
    {
      'id': 'legend_siti_3',
      'name': 'tin of 12-layer kueh lapis',
      'emoji': '🍰',
      'fair': 35,
      'ask': 50,
      'floor': 33,
      'facts': [
        'Twelve thin layers, each one baked separately',
        'Made with real butter and spices',
        'Takes a whole afternoon to bake',
      ],
    },
  ],
  'lee': [
    {
      'id': 'legend_lee',
      'name': '50-year-old aged pu-erh tea cake',
      'emoji': '🍵',
      'fair': 90,
      'ask': 128,
      'floor': 85,
      'facts': [
        'Pressed in Yunnan in the 1970s',
        "Kept in the shop's back room for decades",
        'Earthy and smooth, and it gets better every year',
      ],
    },
    {
      'id': 'legend_lee_2',
      'name': "gift box of hand-cleaned bird's nest",
      'emoji': '🪺',
      'fair': 150,
      'ask': 215,
      'floor': 140,
      'facts': ['Cleaned by hand, from Sarawak', 'A gift box of six pieces', 'Double-boil it with rock sugar'],
    },
    {
      'id': 'legend_lee_3',
      'name': 'jar of 20-year-old dried tangerine peel',
      'emoji': '🍊',
      'fair': 60,
      'ask': 88,
      'floor': 56,
      'facts': [
        'Aged 20 years in Xinhui',
        'The older it is, the more fragrant',
        'A little in soup or red bean dessert is enough',
      ],
    },
  ],
  'boy': [
    {
      'id': 'legend_boy',
      'name': 'vintage wind-up tin robot',
      'emoji': '🤖',
      'fair': 45,
      'ask': 65,
      'floor': 42,
      'facts': [
        'Made in Japan in the 1960s',
        'Still walks and sparks when you wind it up',
        "Ah Boy found it in his grandfather's attic",
      ],
    },
    {
      'id': 'legend_boy_2',
      'name': 'hand-made kampung kite',
      'emoji': '🪁',
      'fair': 30,
      'ask': 44,
      'floor': 28,
      'facts': [
        'Hand-made, with a bamboo frame',
        'Painted by hand in bright colours',
        'Flies beautifully at Marina Barrage',
      ],
    },
    {
      'id': 'legend_boy_3',
      'name': 'tin of vintage glass marbles',
      'emoji': '🔮',
      'fair': 25,
      'ask': 38,
      'floor': 24,
      'facts': [
        'Fifty glass marbles from the 1970s',
        'Still in the original biscuit tin',
        'Ah Boy played with these as a kid',
      ],
    },
  ],
  'wong': [
    {
      'id': 'legend_wong',
      'name': "brass ship's compass",
      'emoji': '🧭',
      'fair': 80,
      'ask': 118,
      'floor': 76,
      'facts': [
        'From a trading ship that sailed between Singapore and Penang in the 1950s',
        'Still points north perfectly',
        'Solid brass, engraved by hand',
      ],
    },
    {
      'id': 'legend_wong_2',
      'name': 'hand-painted 1960s shop signboard',
      'emoji': '🪧',
      'fair': 95,
      'ask': 140,
      'floor': 90,
      'facts': [
        'From an old provision shop, 1960s',
        'Hand-painted Chinese and English letters',
        'Solid wood, still in one piece',
      ],
    },
    {
      'id': 'legend_wong_3',
      'name': 'Peranakan porcelain kamcheng jar',
      'emoji': '🏺',
      'fair': 130,
      'ask': 190,
      'floor': 122,
      'facts': [
        'Pink and green Peranakan porcelain, with its lid',
        'From the early 1900s',
        'Used to hold treats at Peranakan weddings',
      ],
    },
  ],
  'kumar': [
    {
      'id': 'legend_kumar',
      'name': 'secret 21-spice biryani blend',
      'emoji': '🫙',
      'fair': 25,
      'ask': 38,
      'floor': 24,
      'facts': [
        "Her grandmother's recipe from Chennai, never written down",
        '21 spices, roasted and ground by hand this morning',
        'Enough for a big family biryani',
      ],
    },
    {
      'id': 'legend_kumar_2',
      'name': 'jar of sun-aged mango pickle',
      'emoji': '🥭',
      'fair': 18,
      'ask': 26,
      'floor': 17,
      'facts': ["Her mother's recipe, aged a month in the sun", 'Spicy and tangy', 'Goes with curd rice or biryani'],
    },
    {
      'id': 'legend_kumar_3',
      'name': 'brass spice box with six spices',
      'emoji': '🧂',
      'fair': 45,
      'ask': 65,
      'floor': 42,
      'facts': ['A brass masala dabba with six spices inside', 'Made in Chennai', 'The spices were ground this week'],
    },
  ],
  'rosnah': [
    {
      'id': 'legend_rosnah',
      'name': 'royal nasi lemak feast for ten',
      'emoji': '🍛',
      'fair': 120,
      'ask': 168,
      'floor': 112,
      'facts': [
        'Rendang, sambal sotong, ayam goreng and kueh for 10 people',
        'Cooked from 4am this morning',
        'With her famous sambal, made from her own secret chillies',
      ],
    },
    {
      'id': 'legend_rosnah_2',
      'name': 'wedding kueh platter (100 pieces)',
      'emoji': '🍡',
      'fair': 95,
      'ask': 135,
      'floor': 90,
      'facts': ['Ten kinds of kueh, 100 pieces', 'Made fresh at dawn', 'With her famous ondeh-ondeh'],
    },
    {
      'id': 'legend_rosnah_3',
      'name': 'pot of beef rendang for twelve',
      'emoji': '🍲',
      'fair': 85,
      'ask': 120,
      'floor': 80,
      'facts': ['Slow-cooked for six hours', "Her grandmother's Minang recipe", 'Tastes even better the next day'],
    },
  ],
  'faiz': [
    {
      'id': 'legend_faiz',
      'name': 'pair of match-worn signed football boots',
      'emoji': '👟',
      'fair': 120,
      'ask': 175,
      'floor': 112,
      'facts': [
        'Signed by a national team player after a big match at the National Stadium',
        'Worn in one real game',
        'Comes with a photo of the signing',
      ],
    },
    {
      'id': 'legend_faiz_2',
      'name': 'pair of limited-edition retro sneakers',
      'emoji': '👟',
      'fair': 160,
      'ask': 230,
      'floor': 150,
      'facts': ['Only 300 pairs were made, and these were worn once', 'Original box and spare laces', 'Size UK 9'],
    },
    {
      'id': 'legend_faiz_3',
      'name': 'original 1998 football jersey',
      'emoji': '👕',
      'fair': 70,
      'ask': 100,
      'floor': 66,
      'facts': ['An original from 1998, not a copy', 'Bright colours, still in great shape', 'Size L'],
    },
  ],
  'tan': [
    {
      'id': 'legend_tan',
      'name': '100-year-old rattan rocking chair',
      'emoji': '🪑',
      'fair': 70,
      'ask': 98,
      'floor': 66,
      'facts': [
        'Made by hand in a kampung in the 1920s',
        "Ah Ma Tan's late husband's favourite chair",
        'Still rocks smoothly, without a single creak',
      ],
    },
    {
      'id': 'legend_tan_2',
      'name': 'tray of 30 free-range kampung eggs',
      'emoji': '🥚',
      'fair': 22,
      'ask': 32,
      'floor': 21,
      'facts': ["From Ah Ma Tan's cousin's farm in Lim Chu Kang", 'Deep orange yolks', 'Collected yesterday'],
    },
    {
      'id': 'legend_tan_3',
      'name': 'pair of hand-carved wooden clogs',
      'emoji': '🩴',
      'fair': 35,
      'ask': 50,
      'floor': 33,
      'facts': [
        'Hand-carved wooden clogs, called terompah',
        'From the 1950s',
        'Ah Ma Tan wore a pair like this as a girl',
      ],
    },
  ],
};

/// Festival specials: on the 2nd and 5th day of each festival week, this stall has this, whatever the rotation says.
const festivalSpecials = <String, (String, Map<String, Object>)>{
  'xmas': (
    'boy',
    {
      'id': 'legend_fest_xmas',
      'name': 'wind-up Christmas toy train set',
      'emoji': '🚂',
      'fair': 50,
      'ask': 72,
      'floor': 47,
      'facts': [
        'A tin train that runs in a circle around a tiny Christmas tree',
        'Plays a jingle as it goes',
        'Ah Boy only brings it out at Christmas',
      ],
    },
  ),
  'cny': (
    'mei',
    {
      'id': 'legend_fest_cny',
      'name': "box of golden 'big luck' mandarin oranges",
      'emoji': '🍊',
      'fair': 28,
      'ask': 40,
      'floor': 26,
      'facts': [
        'The biggest, sweetest ones, picked for Chinese New Year',
        'A box of 20, with leaves still on',
        'Bring two when you visit: it wishes good luck',
      ],
    },
  ),
  'raya': (
    'rosnah',
    {
      'id': 'legend_fest_raya',
      'name': 'Hari Raya kueh tin collection',
      'emoji': '🍪',
      'fair': 55,
      'ask': 80,
      'floor': 52,
      'facts': [
        'Pineapple tarts, kueh bangkit and almond London cookies',
        'Baked by Auntie Rosnah and her daughters',
        'Five tins, ready for visiting',
      ],
    },
  ),
  'haji': (
    'siti',
    {
      'id': 'legend_fest_haji',
      'name': 'hand-woven songket sampin',
      'emoji': '🧵',
      'fair': 120,
      'ask': 175,
      'floor': 112,
      'facts': [
        'Woven with gold thread on a wooden loom',
        'Takes three weeks to make',
        'Worn for Hari Raya prayers and at weddings',
      ],
    },
  ),
  'deepavali': (
    'kumar',
    {
      'id': 'legend_fest_deepavali',
      'name': 'Deepavali sweets and murukku hamper',
      'emoji': '🪔',
      'fair': 40,
      'ask': 58,
      'floor': 37,
      'facts': ['Murukku, ladoo and mysore pak', 'Made in her own kitchen this week', 'On a brass tray, ready to give'],
    },
  ),
};

/// Every built-in legendary item (rotation and festival specials) by stall, for looking one up by its id.
final Map<String, List<Map<String, Object>>> legendaryByStall = {
  for (final e in legendaryRotation.entries)
    e.key: [
      ...e.value,
      for (final f in festivalSpecials.values)
        if (f.$1 == e.key) f.$2,
    ],
};

/// A day's legendary item: the stall, the item, and what "sold out" is counted by (the day, or the whole event).
typedef Legend = ({String stall, Map<String, Object?> item, String key});

String _plus(String day, int days) {
  final d = DateTime.parse(day);
  return dayKey(DateTime(d.year, d.month, d.day + days));
}

/// The legendary item on [day] ('YYYY-MM-DD'), or null on an ordinary day. [events] are the admin's posted events
/// (already checked with [cleanEvents]).
Legend? legendaryOn(String day, {List<Map> events = const []}) {
  for (final e in events) {
    if ('${e['from']}'.compareTo(day) <= 0 && '${e['to']}'.compareTo(day) >= 0) {
      return (stall: '${e['stall']}', item: Map<String, Object?>.from(e['item'] as Map), key: 'evt-${e['id']}');
    }
  }
  for (final f in festivals) {
    if (day == _plus(f.from, 1) || day == _plus(f.from, 4)) {
      final special = festivalSpecials[f.id.replaceAll(RegExp(r'\d+$'), '')];
      if (special != null) return (stall: special.$1, item: special.$2, key: day);
    }
  }
  final h = stableHash('hawker-haggle-legend-$day');
  if (h % 4 != 0) return null;
  final stalls = legendaryRotation.keys.toList();
  final st = stalls[(h ~/ 4) % stalls.length];
  final items = legendaryRotation[st]!;
  final i = day.compareTo(rotationFrom) < 0 ? 0 : stableHash('hawker-haggle-legend-item-$day') % items.length;
  return (stall: st, item: items[i], key: day);
}

Legend? legendaryToday(DateTime now, {List<Map> events = const []}) => legendaryOn(dayKey(now), events: events);

bool isLegendary(String itemId) => itemId.startsWith('legend_');

/// The next legendary day after [now] (within [within] days): (days from today, stall id). The item stays a secret
/// until the day.
(int, String)? nextLegendary(DateTime now, {List<Map> events = const [], int within = 60}) {
  for (var d = 1; d <= within; d++) {
    final l = legendaryOn(dayKey(DateTime(now.year, now.month, now.day + d)), events: events);
    if (l != null) return (d, l.stall);
  }
  return null;
}

/// The admin's events from the server, checked again here (their facts go to the AI): a known stall, a real date
/// range of at most 7 days, believable prices with as little room as a legendary item, and plain short text. Anything
/// that doesn't pass is dropped; an event overlapping an earlier one is dropped too.
List<Map<String, Object?>> cleanEvents(Object? raw, Set<String> stalls) {
  if (raw is! List) return const [];
  final out = <Map<String, Object?>>[];
  final date = RegExp(r'^\d{4}-\d{2}-\d{2}$');
  final plain = RegExp(r"^[\p{L}\p{M}\p{N} '’\-,&().!:;/]+$", unicode: true);
  bool cleanText(Object? t, int min, int max) {
    if (t is! String) return false;
    final x = t.trim();
    if (x.length < min || x.length > max || !plain.hasMatch(x)) return false;
    final low = x.toLowerCase();
    return !low.contains('http') && !low.contains('www.');
  }

  for (final e in raw.take(20)) {
    if (e is! Map) continue;
    final id = e['id'], item = e['item'];
    final from = '${e['from']}', to = '${e['to']}';
    if (id is! int || id < 1 || !stalls.contains(e['stall']) || item is! Map) continue;
    if (!date.hasMatch(from) || !date.hasMatch(to)) continue;
    final f = DateTime.tryParse(from), t = DateTime.tryParse(to);
    if (f == null || t == null || t.isBefore(f) || t.difference(f).inDays > 6) continue;
    final fair = item['fair'], ask = item['ask'], floor = item['floor'], facts = item['facts'], emoji = item['emoji'];
    if (fair is! num || ask is! num || floor is! num) continue;
    if (!(floor >= 0.5 && floor < fair && fair < ask && ask <= 2000 && floor / ask >= 0.55 && floor / ask <= 0.95)) {
      continue;
    }
    if (!cleanText(item['name'], 3, 50)) continue;
    if (emoji is! String || emoji.isEmpty || emoji.runes.length > 8 || RegExp(r'[\x00-\x7F]').hasMatch(emoji)) continue;
    if (facts is! List || facts.isEmpty || facts.length > 5 || !facts.every((x) => cleanText(x, 3, 140))) continue;
    if (out.any((o) => '${o['from']}'.compareTo(to) <= 0 && '${o['to']}'.compareTo(from) >= 0)) continue;
    out.add({
      'id': id,
      'stall': e['stall'],
      'from': from,
      'to': to,
      'item': {
        'id': 'legend_evt_$id',
        'name': (item['name'] as String).trim(),
        'emoji': emoji,
        'fair': fair,
        'ask': ask,
        'floor': floor,
        'facts': [for (final x in facts) (x as String).trim()],
      },
    });
  }
  return out;
}
