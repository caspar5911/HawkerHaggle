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

/// Silly twists in the middle of a haggle, against an otherwise ordinary market (rare, so they stand out). Each has
/// a quick choice that changes only the stallholder's mood. {name}: the stallholder; {item}: the item. Number-free.
class Twist {
  const Twist(this.id, this.text, this.ai, this.options);
  final String id;
  final String text; // what happens (shown)
  final String ai; // what the AI is told happened
  final List<(String label, double mood, String reaction, String aiChoice)> options;
}

const twists = <Twist>[
  Twist('cat', '🐈 A cat darts off with one of {name}\'s {item}!', 'A cat just ran off with one of your goods.', [
    (
      'Chase the cat',
      1.0,
      '{name} cheers you on: "Catch it! Catch it!"',
      'The customer chased the cat for you; you are grateful.',
    ),
    ('Laugh', 0.2, '{name} laughs too: "Aiyo, that cat again!"', 'The customer laughed about it with you.'),
  ]),
  Twist(
    'phone',
    "📱 {name}'s phone rings: it's the grandchild, on speaker!",
    "Your grandchild called you on speaker in the middle of the haggle.",
    [
      (
        'Say hello',
        0.8,
        '{name} beams: "See? My customer so polite!"',
        'The customer said hello to your grandchild; you are charmed.',
      ),
      (
        'Wait politely',
        0.3,
        '{name} nods at you, holding up one finger.',
        'The customer waited politely while you took the call.',
      ),
      (
        'Keep haggling loudly',
        -0.7,
        '{name} glares and covers the phone.',
        'The customer kept haggling loudly while you were on the phone; you are annoyed.',
      ),
    ],
  ),
  Twist('pigeon', '🐦 A pigeon lands right on the {item}!', 'A pigeon just landed on your goods.', [
    (
      'Shoo it away',
      0.8,
      '{name}: "Thank you ah! Shoo, shoo!"',
      'The customer shooed the pigeon away for you; you are grateful.',
    ),
    (
      'Ask for a pigeon discount',
      -0.4,
      '{name} raises an eyebrow: "Pigeon discount? Funny ah you."',
      'The customer cheekily asked for a "pigeon discount"; you are amused but not impressed.',
    ),
  ]),
  Twist(
    'rain',
    '☔ A sudden downpour: rain drips through the awning!',
    'A sudden downpour started and rain is dripping onto your stall.',
    [
      (
        'Help move the goods',
        1.1,
        '{name}: "Wah, you good one! Thank you!"',
        'The customer helped you move your goods out of the rain; you are very grateful.',
      ),
      (
        'Stay under your umbrella',
        0.0,
        '{name} hurries alone, dripping.',
        'The customer stayed dry under their umbrella while you rushed about.',
      ),
    ],
  ),
  Twist(
    'kid',
    '🧒 A little kid tugs at the counter and asks {name} for a free sweet.',
    'A little kid came up asking you for a free sweet.',
    [
      (
        'Treat the kid',
        1.2,
        'The kid grins; {name} smiles at you warmly.',
        'The customer treated the kid to a sweet; you think they have a good heart.',
      ),
      (
        'Pretend not to see',
        -0.3,
        '{name} sighs and gives the kid a sweet anyway.',
        'The customer ignored the kid; you gave the kid a sweet yourself.',
      ),
    ],
  ),
];
