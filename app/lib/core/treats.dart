/// Reasons to care about every dollar, and little surprises: the savings jar and its goals, freebies from a
/// stallholder who likes you, small dilemmas with no perfect answer, and a book of favourite lines. Progress only:
/// no prices, no XP, nothing the engine or the Python reference sees.
library;

/// One thing in the 🛍️ shop: bought once with your jar, and it does something for you from then on.
class Goal {
  const Goal(this.id, this.emoji, this.name, this.cost, this.tier, this.does, this.bought);
  final String id, emoji, name;
  final double cost;
  final String tier; // starter, growing, serious, dream
  final String does; // what it does for you (shown in the shop)
  final String bought; // said when you buy it
}

/// The shop's tiers, in order.
const goalTiers = [('starter', 'Starter'), ('growing', 'Growing'), ('serious', 'Serious'), ('dream', 'Dream')];

/// Everything in the 🛍️ shop, cheapest first in each tier. Bigger things make the next ones easier to reach. (Ids are
/// stored when bought: never rename one.)
const goals = <Goal>[
  Goal(
    'notebook',
    '📒',
    'Price notebook',
    25,
    'starter',
    'The market shows the best price you ever paid for each thing.',
    'Now you can see your best price on every stall.',
  ),
  Goal(
    'cake',
    '🎂',
    "Mum's birthday cake",
    30,
    'starter',
    'Mum gives you \$5 more pocket money every day.',
    'Mum: Wah, a cake for me? So sweet of you! (\$5 more pocket money every day.)',
  ),
  Goal(
    'charm',
    '🍀',
    'Lucky charm',
    40,
    'starter',
    'Every stallholder starts with more patience with you.',
    'They seem a little more patient already.',
  ),
  Goal(
    'awning',
    '⛱️',
    'A bright awning for your stall',
    80,
    'starter',
    'Customers at your own stall pay 5% more.',
    'Your stall looks lovely: customers pay a little more.',
  ),
  Goal(
    'flowers',
    '🌸',
    'Flowers for the stallholders',
    100,
    'growing',
    'Every stallholder starts in a better mood with you.',
    'They love the flowers! Everyone is in a better mood with you.',
  ),
  Goal(
    'shelf',
    '📦',
    'A bigger shelf',
    120,
    'growing',
    'Your stock holds 15 things instead of 10.',
    'Room for 15 things now.',
  ),
  Goal(
    'scooter',
    '🛵',
    'A scooter for deliveries',
    150,
    'growing',
    'Deliveries: each new day you play, one thing from your stock sells by itself (at 90% of the market price).',
    'Vroom! Every new day you play, one thing goes out for delivery.',
  ),
  Goal(
    'watch',
    '⌚',
    'Calculator watch',
    180,
    'growing',
    'While you haggle, see how much you have got off the first price.',
    'Beep! Now you can see your discount as you haggle.',
  ),
  Goal(
    'piggy',
    '🐷',
    'Piggy bank',
    200,
    'growing',
    'Your jar grows by 2% each new day you play (up to \$5 a day).',
    'Oink! Your savings grow a little every day now.',
  ),
  Goal(
    'sign',
    '🪧',
    'A shop sign',
    200,
    'serious',
    'Big-spender customers come to your stall more often.',
    'People can see your stall from far away now.',
  ),
  Goal(
    'icebox',
    '🧊',
    'An ice box',
    250,
    'serious',
    'Fresh things (fish, prawns, fruit, kueh, eggs) sell for 10% more at your stall.',
    'Everything stays fresh and cold.',
  ),
  Goal(
    'neon',
    '💡',
    'A neon sign',
    300,
    'serious',
    'Customers at your own stall pay another 5% more.',
    'Your stall glows at night now!',
  ),
  Goal('storeroom', '🗄️', 'A storeroom', 350, 'serious', 'Your stock holds 25 things.', 'Room for 25 things now.'),
  Goal(
    'van',
    '🚚',
    'A food van',
    500,
    'serious',
    'Two more deliveries each new day you play.',
    'Your own van! Three deliveries a day now (with the scooter).',
  ),
  Goal(
    'stall2',
    '🏪',
    'A second stall',
    1200,
    'dream',
    'Three more deliveries each new day you play.',
    'A second stall of your own! It sells three more things every day.',
  ),
  Goal('golden', '✨', 'A golden stall', 2000, 'dream', 'Your own stall shines gold.', 'Your stall shines gold!'),
  Goal(
    'wall',
    '👑',
    'Your name on the hawker centre wall',
    3000,
    'dream',
    'The final trophy: a crown next to your name everywhere.',
    'Your name is on the wall! 👑 Hawker legend.',
  ),
];

/// Fresh things that the ice box keeps cold (they sell for more at your stall).
const freshThings = {'mei/durian', 'mei/mango', 'lim/pomfret', 'lim/prawns', 'siti/kueh', 'rosnah/ondeh', 'tan/eggs'};

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
