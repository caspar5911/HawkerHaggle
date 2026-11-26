/// ✨ Legendary items: on about one day in four, one stall has something rare, for that day only. It's the same stall
/// and item for everyone that day (chosen from the date alone), so friends can talk about it. Harder to haggle for:
/// less room between the asking price and the lowest, and a stallholder in less of a mood to chat. One per player per
/// day: once bought, it's sold out until the next one.
///
/// App only: the market server, Mum's list and the daily challenges never see these items.
library;

import 'progress.dart' show dayKey, stableHash;

const legendaryItems = <String, Map<String, Object>>{
  'mei': {
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
  'lim': {
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
  'raj': {
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
  'siti': {
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
  'lee': {
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
  'boy': {
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
  'wong': {
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
  'kumar': {
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
  'rosnah': {
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
  'faiz': {
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
  'tan': {
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
};

/// The legendary item on [day] ('YYYY-MM-DD'), as (stall id, item), or null on an ordinary day.
(String, Map<String, Object>)? legendaryOn(String day) {
  final h = stableHash('hawker-haggle-legend-$day');
  if (h % 4 != 0) return null;
  final stalls = legendaryItems.keys.toList();
  final st = stalls[(h ~/ 4) % stalls.length];
  return (st, legendaryItems[st]!);
}

(String, Map<String, Object>)? legendaryToday(DateTime now) => legendaryOn(dayKey(now));

bool isLegendary(String itemId) => itemId.startsWith('legend_');
