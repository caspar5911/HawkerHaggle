/// Story arcs: each regular has a little story in three chapters. A chapter opens with friendship (hearts) and is
/// finished by a haggle that does what it asks. Progress only: no prices or engine changes, no XP (the month's pacing
/// stays as tested); finishing a whole story earns a sticker.
class Chapter {
  const Chapter(this.hearts, this.title, this.ask, this.done, this.check);
  final int hearts; // opens at this many hearts
  final String title;
  final String ask; // what to do
  final String done; // what happens when it's done
  final bool Function(Map record, Map? previous)
  check; // record: the haggle just finished; previous: the last chapter's
}

bool _deal(Map r, String stall, [String? item]) =>
    r['result'] == 'deal' && r['stall'] == stall && (item == null || r['item'] == item);

const arcTitles = {
  'mei': "Auntie Mei's grandson's wedding",
  'lim': "Uncle Lim's last stall?",
  'raj': "Boss Raj's big order",
  'siti': "Kak Siti's batik show",
};

final arcs = <String, List<Chapter>>{
  'mei': [
    Chapter(
      1,
      'The tea ceremony',
      "Auntie Mei's grandson is getting married! Buy a box of mangoes from her for the tea ceremony.",
      'She wraps the mangoes in red paper: "For good luck, my dear!"',
      (r, _) => _deal(r, 'mei', 'mango'),
    ),
    Chapter(
      2,
      'The wedding dinner',
      'She wants Uncle Lim\'s prawns for the dinner, but he\'s stubborn. Get them at a good price (2 stars or more).',
      'Uncle Lim grumbles, then adds a few extra prawns "for the auntie".',
      (r, _) => _deal(r, 'lim', 'prawns') && ((r['stars'] ?? 0) as num) >= 2,
    ),
    Chapter(
      3,
      'The big day',
      'The wedding! Visit Auntie Mei and close one more deal: she has something for you.',
      'She hands you a red packet and a wedding invitation with your name on it. 💌',
      (r, _) => _deal(r, 'mei'),
    ),
  ],
  'lim': [
    Chapter(
      1,
      'Sore knees',
      "Uncle Lim's son wants him to retire. Buy a pomfret to show the stall still has customers.",
      '"Hmph. One customer only." But he stands a little straighter.',
      (r, _) => _deal(r, 'lim', 'pomfret'),
    ),
    Chapter(
      2,
      'A real regular',
      'Come back on another day and buy from him again. Regulars keep a stall alive.',
      '"You again ah." He almost smiles.',
      (r, prev) => _deal(r, 'lim') && prev != null && r['day'] != prev['day'],
    ),
    Chapter(
      3,
      'Father and son',
      'His son comes to help at the stall. Close a deal with them both.',
      'His son packs your fish while Uncle Lim tells you the stall will stay. He smiles properly this time. 🐟',
      (r, _) => _deal(r, 'lim'),
    ),
  ],
  'raj': [
    Chapter(
      1,
      'First customer',
      'Boss Raj is saving up for a bigger stall. Buy a phone case.',
      '"First sale tonight, boss! Lucky customer!"',
      (r, _) => _deal(r, 'raj', 'case'),
    ),
    Chapter(
      2,
      'Double up',
      'Help him hit his target: buy two of something in one go.',
      'He ticks a line in his notebook: "Target, almost there!"',
      (r, _) => _deal(r, 'raj') && ((r['qty'] ?? 1) as num) >= 2,
    ),
    Chapter(
      3,
      'The new stall',
      'He got the bigger stall! Come and buy at the opening.',
      'Boss Raj cuts a ribbon made of charging cables and gives you the first receipt. 🎉',
      (r, _) => _deal(r, 'raj'),
    ),
  ],
  'siti': [
    Chapter(
      1,
      'The scarf',
      'Kak Siti is preparing her batik for a craft show. Buy a scarf to cheer her on.',
      '"Terima kasih! You are my first fan."',
      (r, _) => _deal(r, 'siti', 'scarf'),
    ),
    Chapter(
      2,
      'Kind words',
      'She is nervous about the show. Say something nice about her work, then buy from her.',
      'She smiles: "Okay, I feel braver already."',
      (r, _) => _deal(r, 'siti') && ((r['tactics'] as List?) ?? const []).contains('compliment'),
    ),
    Chapter(
      3,
      'The show',
      'The show was a success! Visit her stall and close a deal.',
      'She shows you a photo of her batik on the wall at the show, with a ribbon. 🏵️',
      (r, _) => _deal(r, 'siti'),
    ),
  ],
};
