/// Reasons to care about every dollar, and little surprises: the savings jar and its goals, freebies from a
/// stallholder who likes you, small dilemmas with no perfect answer, and a book of favourite lines. Progress only:
/// no prices, no XP, nothing the engine or the Python reference sees.
library;

/// Things to save up for. Buying one empties that much from the jar.
const goals = <(String, String, String, double, String)>[
  ('cake', '🎂', "Mum's birthday cake", 30, 'Mum: Wah, a cake for me? So sweet of you!'),
  ('awning', '⛱️', 'A bright new awning for your own stall', 80, 'Customers at your stall pay a little more.'),
  ('scooter', '🛵', 'A little scooter to get around the markets', 150, 'Vroom! The whole island is yours.'),
];

/// What each stallholder might throw in for a customer they like (it goes into your stock, free).
const freebies = <String, (String, String, double)>{
  'mei': ('lucky orange', '🍊', 2),
  'lim': ('handful of ikan bilis', '🐟', 3),
  'raj': ('charging cable', '🔌', 4),
  'siti': ('small batik hanky', '🧣', 5),
  'lee': ('sachet of tea', '🍵', 3),
  'boy': ('spare yo-yo string', '🪀', 2),
  'wong': ('old picture postcard', '🖼️', 4),
  'kumar': ('packet of curry leaves', '🌿', 2),
  'rosnah': ('extra ondeh-ondeh', '🍡', 2),
  'faiz': ('pair of shoelaces', '👟', 3),
  'tan': ('kampung egg', '🥚', 1),
};

/// A choice with a cost: help a stallholder out (from your jar) for friendship, or not. Number-free text; the cost
/// is shown on the button.
const dilemmas = <String, (String, double)>{
  'mei': ("Auntie Mei's grandson needs new school shoes, and she sighs about it. Leave a little extra?", 3),
  'lim': ("Uncle Lim's ice machine broke this morning and he's grumbling about the repair. Help a bit?", 4),
  'raj': ('Boss Raj is a little short of his stall rent this week. Round up for him?', 3),
  'siti': ('Kak Siti needs fabric for her batik show and money is tight. Chip in?', 4),
  'lee': ("Madam Lee's teapot cracked; she shrugs, but you can tell she's sad. Leave something for a new one?", 3),
  'boy': ("Ah Boy's RC car battery died before a race with the kids. Help him buy one?", 3),
  'wong': ('Uncle Wong wants to fix the radio for the old folks home. Contribute a little?', 4),
  'kumar': ("Madam Kumar's grinder needs a new blade before the festival orders. Help out?", 4),
  'rosnah': ("Auntie Rosnah is saving up for her daughter's wedding food. Add a little?", 4),
  'faiz': ("Bro Faiz's football club needs a new ball for the kids. Chip in?", 3),
  'tan': ("Ah Ma Tan's chicken coop roof is leaking. Help fix it?", 3),
};

const quotesKept = 50;
const quoteMaxChars = 220;
