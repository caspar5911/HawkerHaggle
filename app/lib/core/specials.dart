// 🗓️ This week's special: every stall has a third thing to haggle for, a different one each week (two take turns).
//
// They live here, not in the stalls' item lists, so Mum's list, the daily challenges, customer orders and co-op rooms
// (which use the regular items, and the server's copy of them) never change. A special can be bought, goes into your
// stock like any other thing, and is remembered after its week ends. Prices are in the same range as the stall's own.
// The facts have no numbers in them on purpose (the stallholder may only say the game's prices).

const specials = <String, List<Map<String, Object>>>{
  'mei': [
    {
      'id': 'pineapple',
      'name': 'Sarawak pineapple',
      'emoji': '🍍',
      'fair': 6,
      'ask': 9,
      'floor': 5,
      'facts': [
        'Sarawak pineapple, small and very sweet',
        'Smell the bottom: sweet smell means ripe',
        'Auntie can skin and cut it for you, free',
        'Keep it in the fridge once cut',
        'Good for pineapple tarts and fried rice',
      ],
    },
    {
      'id': 'coconut',
      'name': 'young coconut',
      'emoji': '🥥',
      'fair': 5,
      'ask': 7.5,
      'floor': 4,
      'facts': [
        'Young Thai coconut, opened on the spot',
        'Drink the water cold, then scoop the soft flesh',
        'Very refreshing on a hot day',
        'Best drunk the same day',
        'Comes with a straw and a spoon',
      ],
    },
  ],
  'lim': [
    {
      'id': 'crab',
      'name': 'Sri Lankan crab',
      'emoji': '🦀',
      'fair': 26,
      'ask': 38,
      'floor': 22,
      'facts': [
        'Big Sri Lankan mud crab, still alive',
        'Heavy for its size means lots of meat',
        'Perfect for chilli crab or black pepper crab',
        'Cook it the same day',
        'Uncle ties the claws so it cannot pinch you',
      ],
    },
    {
      'id': 'squid',
      'name': 'fresh squid',
      'emoji': '🦑',
      'fair': 12,
      'ask': 18,
      'floor': 10,
      'facts': [
        'Caught this morning, clear eyes and shiny skin',
        'Uncle can clean it for you',
        'Good for sambal sotong or deep-fried rings',
        'Cook it fast and hot or it goes rubbery',
        'Keep it on ice until you cook it',
      ],
    },
  ],
  'raj': [
    {
      'id': 'earbuds',
      'name': 'wireless earbuds',
      'emoji': '🎧',
      'fair': 30,
      'ask': 54,
      'floor': 24,
      'facts': [
        'Bluetooth earbuds with a charging case',
        'Comes with small, medium and large ear tips',
        'Shop warranty: bring it back if it fails within the month',
        'Works with Android phones and iPhones',
        'Box is sealed, brand new',
      ],
    },
    {
      'id': 'cable',
      'name': 'phone charging cable',
      'emoji': '🔌',
      'fair': 5,
      'ask': 9,
      'floor': 4,
      'facts': [
        'Strong braided cable, does not tangle easily',
        'Fast charging',
        'Fits most new phones',
        'Boss Raj tests it in front of you',
        'Longer than the one that came with your phone',
      ],
    },
  ],
  'siti': [
    {
      'id': 'sarong',
      'name': 'batik sarong',
      'emoji': '👘',
      'fair': 30,
      'ask': 48,
      'floor': 25,
      'single': true,
      'facts': [
        'Hand-drawn batik from Pekalongan, Indonesia',
        'Soft cotton, colours do not run in the wash',
        'The pattern is one of a kind',
        'Wear it, or hang it on the wall',
        'Kak Siti can show you how to tie it',
      ],
    },
    {
      'id': 'lapis',
      'name': 'kueh lapis (a whole log)',
      'emoji': '🍰',
      'fair': 16,
      'ask': 24,
      'floor': 13,
      'facts': [
        'Layer cake, baked one thin layer at a time',
        'Rich with butter and a little spice',
        'Takes a whole afternoon to bake',
        'Keeps about a week in the fridge',
        'A favourite gift at Hari Raya and Chinese New Year',
      ],
    },
  ],
  'lee': [
    {
      'id': 'puer',
      'name': 'cake of pu-erh tea',
      'emoji': '🫖',
      'fair': 35,
      'ask': 52,
      'floor': 29,
      'facts': [
        'Pressed pu-erh tea from Yunnan, China',
        'Aged for years, smooth and earthy',
        'Break off a small piece for each pot',
        'Keep it dry, away from strong smells',
        'Gets better the longer you keep it',
      ],
    },
    {
      'id': 'abalone',
      'name': 'tin of abalone',
      'emoji': '🥫',
      'fair': 48,
      'ask': 70,
      'floor': 40,
      'facts': [
        'Braised abalone from Australia, ready to eat',
        'A favourite for the Chinese New Year reunion dinner',
        'Warm the tin in hot water before opening',
        'Slice it thin and pour the sauce over',
        'Keeps for years if the tin is not opened',
      ],
    },
  ],
  'boy': [
    {
      'id': 'kite',
      'name': 'dragon kite',
      'emoji': '🪁',
      'fair': 10,
      'ask': 16,
      'floor': 8,
      'facts': [
        'Long dragon kite with a colourful tail',
        'Flies best on a windy afternoon at Marina Barrage',
        'Comes with string on a handle',
        'Folds up small to carry',
        'Ah Boy shows you how to launch it',
      ],
    },
    {
      'id': 'robot',
      'name': 'wind-up tin robot',
      'emoji': '🤖',
      'fair': 14,
      'ask': 22,
      'floor': 11,
      'facts': [
        'Old-style tin robot, walks when you wind it',
        'Sparks light up in its chest as it walks',
        'No batteries needed',
        'A nice toy and a nice decoration',
        'The key is attached so you cannot lose it',
      ],
    },
  ],
  'wong': [
    {
      'id': 'camera',
      'name': 'old film camera',
      'emoji': '📷',
      'fair': 55,
      'ask': 85,
      'floor': 46,
      'single': true,
      'facts': [
        'Film camera from the seventies, still works',
        'Heavy metal body, smooth shutter',
        'Uncle Wong found it at a house in Katong',
        'You can still buy film for it',
        'Only one, and it comes with its leather case',
      ],
    },
    {
      'id': 'alarmclock',
      'name': 'brass alarm clock',
      'emoji': '⏰',
      'fair': 30,
      'ask': 45,
      'floor': 25,
      'single': true,
      'facts': [
        'Wind-up brass alarm clock with two bells on top',
        'Ticks loudly and rings very loudly',
        'Uncle Wong polished it himself',
        'From an old coffee shop in Chinatown',
        'Only one',
      ],
    },
  ],
  'kumar': [
    {
      'id': 'cardamom',
      'name': 'bag of green cardamom',
      'emoji': '🌿',
      'fair': 12,
      'ask': 18,
      'floor': 10,
      'facts': [
        'Green cardamom pods from Kerala, India',
        'Crush a pod to smell it: sweet and fresh',
        'For biryani, curries and masala tea',
        'Keep it in a closed jar',
        'Madam Kumar picks out the broken pods',
      ],
    },
    {
      'id': 'ghee',
      'name': 'jar of ghee',
      'emoji': '🧈',
      'fair': 10,
      'ask': 15,
      'floor': 8.5,
      'facts': [
        'Pure ghee, golden and nutty',
        'For prata, biryani and sweets',
        'Does not need the fridge',
        'A spoonful makes rice smell wonderful',
        'Madam Kumar uses the same one at home',
      ],
    },
  ],
  'rosnah': [
    {
      'id': 'dadar',
      'name': 'box of kueh dadar',
      'emoji': '🥞',
      'fair': 12,
      'ask': 18,
      'floor': 10,
      'facts': [
        'Green pandan crepes rolled around sweet coconut',
        'The coconut is cooked with gula melaka',
        'Made this morning by Auntie Rosnah',
        'Best eaten today',
        'Soft, sweet and fragrant',
      ],
    },
    {
      'id': 'sambal',
      'name': 'jar of homemade sambal',
      'emoji': '🌶️',
      'fair': 8,
      'ask': 12,
      'floor': 6.5,
      'facts': [
        "Auntie Rosnah's own sambal, the same as on her nasi lemak",
        'Spicy, a little sweet, with dried shrimp',
        'Keep it in the fridge after opening',
        'Goes with rice, eggs, noodles, everything',
        'Tourists take it home in their suitcase',
      ],
    },
  ],
  'faiz': [
    {
      'id': 'baseballcap',
      'name': 'pre-loved baseball cap',
      'emoji': '🧢',
      'fair': 12,
      'ask': 20,
      'floor': 10,
      'single': true,
      'facts': [
        'Pre-loved cap, washed and like new',
        'Adjustable strap at the back',
        'A rare colour, Bro Faiz has only this one',
        'Keeps the sun off at the football field',
        'Bro Faiz checked the stitching himself',
      ],
    },
    {
      'id': 'boots',
      'name': 'pair of pre-loved football boots',
      'emoji': '🥾',
      'fair': 35,
      'ask': 55,
      'floor': 29,
      'single': true,
      'facts': [
        'Pre-loved football boots, studs still good',
        'Cleaned and with new laces',
        'Light and comfy, used for one season',
        'Good for grass fields',
        'Only one pair',
      ],
    },
  ],
  'tan': [
    {
      'id': 'kaya',
      'name': 'jar of kaya',
      'emoji': '🍯',
      'fair': 5,
      'ask': 8,
      'floor': 4,
      'facts': [
        'Homemade coconut and egg jam, with pandan',
        'For kaya toast with butter',
        'Keep it in the fridge',
        'Ah Ma Tan stirs it for hours over a low fire',
        'Smooth and not too sweet',
      ],
    },
    {
      'id': 'biscuits',
      'name': 'tin of old-school biscuits',
      'emoji': '🍪',
      'fair': 9,
      'ask': 14,
      'floor': 7.5,
      'facts': [
        'Old-school biscuits in a big tin, like in the old provision shops',
        'Gem biscuits, iced gems and butter cookies',
        'Kids love the colourful iced gems',
        'Close the tin well or they go soft',
        'The tin is nice to keep after',
      ],
    },
  ],
};

/// Which week it is (Monday to Sunday), counted from a Monday.
int weekNumber(DateTime now) =>
    (DateTime.utc(now.year, now.month, now.day).difference(DateTime.utc(2026, 1, 5)).inDays / 7).floor();

/// This week's special at a stall (none if it has none).
Map<String, Object>? specialFor(String stall, DateTime now) {
  final l = specials[stall];
  if (l == null || l.isEmpty) return null;
  final i = specials.keys.toList().indexOf(stall);
  return l[(weekNumber(now) + i) % l.length];
}

/// Any special of this stall (this week's or not), by id: for things already bought.
Map<String, Object>? anySpecial(String stall, String item) =>
    specials[stall]?.where((x) => x['id'] == item).firstOrNull;
