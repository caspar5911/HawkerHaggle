/// How to haggle: a "next time" tip after each haggle (from what really happened in it), and the 📖 Haggling guide, a
/// set of tricks the game really rewards. Each trick stays hidden until the player has used it once, so the guide
/// fills in as they play instead of giving every secret away on day one.
library;

/// One tip for next time, from how this haggle went. The most useful one only, in plain words, no numbers from the
/// stallholder's secret limit. [firstOffer] is the first offer as a share of the opening price; [kindWordNoted] is
/// true when the closeness note already said "a kind word first" (so it isn't said twice); [single]: a one-of-a-kind
/// item, so no "ask for a price for two".
String coachTip({
  required String result,
  required int rounds,
  required int stars,
  required Set<String> tactics,
  required Set<String> events,
  required bool walkedAway,
  required bool calledBack,
  required String who,
  double? firstOffer,
  bool kindWordNoted = false,
  bool single = false,
}) {
  final deal = result == 'deal';
  final sweet = tactics.contains('compliment') || tactics.contains('regular');
  if (result == 'lost') {
    return 'Auntie Rose was faster! When she shows up, skip the chit-chat and make your offers quickly.';
  }
  if (events.contains('insulted') || events.contains('rude')) {
    return 'That made $who cross and cost you patience. Start at about two-thirds of the price, not far below, '
        'then come up a little at a time.';
  }
  if (result == 'refused') {
    return "$who ran out of patience. When she says it's her last price, take it or walk away instead of offering "
        'again: every offer uses up a bit of patience ❤️.';
  }
  if (result == 'walked' && !calledBack) {
    return 'Walking away works best near her last price, after a friendly chat. Then she sometimes calls you back '
        'with a better one.';
  }
  if (deal && rounds <= 1) {
    return 'You paid her first price! Stallholders always start high: offer about 70% first. You can always come '
        'up.';
  }
  if (deal && firstOffer != null && firstOffer > 0.85) {
    return 'Your first offer was close to her price, so there was little left to bargain. Start lower (about 70%) '
        'and meet in the middle.';
  }
  if (deal && stars < 3 && events.contains('final') && !walkedAway) {
    return "When she says it's her last price, try walking away 🚶. Sometimes they call you back with a better one.";
  }
  if (deal && stars < 3 && !sweet && !kindWordNoted) {
    return 'Be nice first: a compliment 😍 or "I come here every week" makes $who softer before you talk price.';
  }
  if (deal && stars < 3 && !tactics.contains('competitor') && !tactics.contains('bulk')) {
    return single // one of a kind: there's no second one to ask about
        ? 'Early on, while the price is still high, try "the stall next door is cheaper" 👀.'
        : 'Early on, while the price is still high, try "the stall next door is cheaper" 👀, or ask for a price for '
              'two 🛍️.';
  }
  if (deal && stars >= 3) {
    return 'A perfect haggle! Try a harder stall, a ✨ legendary item, or Hard mode in Settings.';
  }
  return "Try a trick you haven't used yet: the 📖 Haggling guide (under Me) shows which ones are left.";
}

/// A trick: (id, emoji, title, how it works, an example line, a hint while it's still hidden).
typedef Trick = (String, String, String, String, String, String);

const tricks = <Trick>[
  (
    'open',
    '💰',
    'Start low, but not too low',
    'Stallholders always ask more than they expect to get. Open at about two-thirds of their price and come up a '
        'little each time. Far too low makes them cross.',
    '"Auntie, \$12 can or not?"',
    'Close a deal well below the first price.',
  ),
  (
    'compliment',
    '😍',
    'Say something nice',
    'A kind word about their goods (or their stall) puts them in a better mood, and a happy stallholder comes down '
        'more. Try one sincere compliment first. Auntie Mei catches on quickly if you repeat yourself.',
    '"Wah, your mangoes look so sweet today!"',
    'Be nice before you talk price.',
  ),
  (
    'regular',
    '🙋',
    'Be a regular',
    'Stallholders look after their regulars. Saying you come every week helps, and coming back often really does '
        'make them your friend (hearts 💛).',
    '"I buy from you every week one!"',
    'Tell them you come here often.',
  ),
  (
    'competitor',
    '👀',
    'Mention a cheaper stall',
    'Saying the stall next door is cheaper can make them drop the price to keep you. Say it early, while their '
        'price is still high: near their lowest it only annoys them (stubborn ones sooner).',
    '"The one over there selling cheaper leh."',
    'Let them know there are other stalls.',
  ),
  (
    'bulk',
    '🛍️',
    'Buy two',
    'Asking for a price for two gets a better price for each one. Good when you need more than one anyway. '
        'Not for one-of-a-kind things (antiques, pre-loved, legendary): there is only one!',
    '"If I take two, how much?"',
    'Ask about buying more than one.',
  ),
  (
    'budget',
    '👛',
    'Name your budget',
    'Telling them how much you have makes them decide if they can meet you there. Use a believable number.',
    '"I only got \$15 leh."',
    'Tell them how much you can spend.',
  ),
  (
    'plead',
    '🥺',
    'Ask nicely for a discount',
    'Sometimes a polite "can cheaper?" is all it takes. Ask once or twice; beg too much and they get tired of it.',
    '"Auntie, can give a bit of discount or not?"',
    'Just ask, politely.',
  ),
  (
    'final',
    '🧱',
    'Know a last price',
    'When they say it\'s their last price, offering lower again only uses up patience. Take it, or walk away.',
    '"OK lah, deal!"',
    'Haggle until they say it\'s their last price.',
  ),
  (
    'walk',
    '🚶',
    'Walk away',
    'Near their last price, after a friendly chat, walking away can get you called back with a better price. Rude or '
        'far apart, and they just let you go.',
    '"Never mind, I look around first."',
    'Get called back after walking away.',
  ),
  (
    'patience',
    '❤️',
    'Watch their patience',
    'Every move uses up a bit of patience (the hearts at the top). When it runs out, there\'s no sale. Don\'t drag it '
        'out with tiny steps.',
    '"OK OK, last one: \$14?"',
    'Play a few haggles, or see what happens when patience runs out.',
  ),
  (
    'softspot',
    '💡',
    'Find their soft spot',
    'Every stallholder loves talking about something (Uncle Lim\'s fishing trips, Auntie Mei\'s grandson). Find it '
        'and they warm up a lot. Their profile has clues.',
    '"Uncle, you still go fishing on weekends?"',
    'Chat about what they love. Their profile has clues.',
  ),
  (
    'tagteam',
    '🤜',
    'Tag team',
    'Haggling with a friend: one sweet-talks, the other makes the offer. The stallholder can\'t help being charmed.',
    '(Friend) "So nice your stall!"  (You) "\$12 can?"',
    'Haggle together with a friend (👥).',
  ),
];

/// Which tricks the player has used, from their past haggles and soft spots found.
Set<String> learnedTricks(List<Map> haggles, {int softSpots = 0}) {
  final out = <String>{};
  for (final h in haggles) {
    final t = {...(h['tactics'] as List? ?? const []).map((x) => '$x')};
    if (h['result'] == 'deal' && ((h['saved'] ?? 0) as num) >= 0.15) out.add('open');
    for (final k in const ['compliment', 'regular', 'competitor', 'bulk', 'budget']) {
      if (t.contains(k)) out.add(k);
    }
    if (((h['qty'] ?? 1) as num) >= 2) out.add('bulk');
    if (t.contains('plead') || t.contains('pity')) out.add('plead');
    if (h['heard_final'] == true) out.add('final');
    if (h['called_back'] == true) out.add('walk');
    if (h['result'] == 'refused') out.add('patience');
    if (((h['combos'] ?? 0) as num) > 0) out.add('tagteam');
  }
  if (haggles.length >= 5) out.add('patience');
  if (softSpots > 0) out.add('softspot');
  return out;
}

/// Real life, briefly: where haggling is (and isn't) done in Singapore, and how to do it kindly.
const realLife = [
  '🍜 At hawker centres and food stalls, prices are fixed. Nobody bargains for their chicken rice!',
  '🛍️ Bargaining is normal at flea markets, pasar malams and some souvenir stalls, and when you buy several things '
      'at once.',
  '😊 Be polite and smile. "Auntie, can give a bit of discount?" goes much further than a very low offer.',
  '🙏 If they say no, take it nicely. Small stallholders earn very little on each sale.',
  '⚖️ Check whether the price is per piece, per bag or per kilo before you agree.',
];
