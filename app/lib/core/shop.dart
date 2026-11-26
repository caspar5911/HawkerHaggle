// Run your own stall: the roles reversed. You sell; customers (made-up characters) try to bargain you down.
// Its own little engine, separate from the stallholders' one (which the Python reference checks). Code owns every
// number: each customer's secret most they'll pay, their offers, their patience. The AI only writes the customer's
// words, with the prices the code gives it.
import 'dart:math' as math;

import 'ai_client.dart';
import 'py.dart';
import 'voice.dart';

class Product {
  const Product(this.id, this.name, this.emoji, this.cost, this.fair);
  final String id, name, emoji;
  final double cost; // what you paid for it
  final double fair; // what it's usually sold for
}

const products = [
  Product('mango', 'box of mangoes', '🥭', 8, 12),
  Product('case', 'phone case', '📱', 4, 10),
  Product('scarf', 'batik scarf', '🧣', 18, 32),
];

class Customer {
  const Customer(
    this.id,
    this.name,
    this.persona,
    this.voice,
    this.look, {
    required this.most,
    required this.opens,
    required this.patience,
    required this.step,
    required this.lines,
    this.clue = '',
    this.loves = const {},
  });
  final String id, name, persona, voice;
  final String clue; // what you can tell by looking at them (shown at your stall)
  final Set<String> loves; // the kinds of things they love (see kindOf): they pay more for those
  final Map<String, String> look;
  final double most; // the most they'll pay, as a share of the fair price (a little random around it)
  final double opens; // their first offer, as a share of the fair price
  final int patience; // how many counters before they walk
  final double step; // how far they move towards your price each time
  final Map<String, List<String>> lines; // ready-made lines: {offer}, {ask}, {price}, {item}
}

/// What kind of thing it is, for what customers love: fresh food, souvenirs, toys and gadgets, premium things.
String kindOf(String key) => switch (key) {
  'mei/durian' || 'lim/prawns' || 'lee/scallops' || 'kumar/saffron' || 'wong/radio' || 'wong/tiffin' => 'premium',
  'mei/mango' || 'lim/pomfret' || 'siti/kueh' || 'rosnah/ondeh' || 'rosnah/tray' || 'tan/eggs' || 'mango' => 'fresh',
  'siti/scarf' || 'lee/oolong' || 'kumar/masala' || 'scarf' => 'souvenir',
  'raj/case' || 'raj/powerbank' || 'boy/rccar' || 'boy/yoyo' || 'faiz/sneakers' || 'faiz/jersey' || 'case' => 'toy',
  _ => 'other',
};

/// A loved thing: they pay up to a quarter more, and open higher.
const loveMore = 1.25, loveOpens = 1.1;

const customers = [
  Customer(
    'uncle',
    'Uncle Ong',
    'A kiasu retired uncle who counts every cent and loves a bargain, but pays fairly for good stuff.',
    "Gruff and short. Calls the seller 'boss', uses 'aiyah', 'so ex' and 'can or not'.",
    {'skin': '#E6BF9C', 'hair': '#BDBDBD', 'shirt': '#90A4AE', 'apron': '#90A4AE', 'accessory': 'glasses'},
    most: 1.05,
    opens: 0.55,
    patience: 5,
    step: 0.35,
    clue: '👴 Counts every cent',
    loves: {'fresh'},
    lines: {
      'greet': ['Boss, this {item}. {offer} can or not?', 'Aiyah, {item} how much? I give you {offer}.'],
      'raise': ['{ask}? So ex! Okay, {offer} lah.', 'Aiyah boss, {ask} cannot. {offer}.'],
      'annoyed': ['{ask}?! You think I rich ah?', 'Wah, {ask}? Daylight robbery!'],
      'accept': ['Okay lah, {price}. Pack for me.', 'Hmph. {price}, deal.'],
      'thanks': ['{price}, good. Thank you boss.', 'Okay, {price}. Steady.'],
      'happy': ['Hehe, okay boss. {offer} can?', 'You funny. Still {offer} lah.'],
      'impatient': ['Talk so much. {offer}, yes or no?', 'Boss, I busy. {offer}.'],
      'walk': ['Forget it. I go next stall.', 'Too ex. Bye.'],
    },
  ),
  Customer(
    'tourist',
    'Emma the tourist',
    'A cheerful tourist on her first trip to Singapore, unsure of local prices and happy to pay a bit more for something nice.',
    'Friendly and polite, curious, says "lovely" and "oh wow", asks about the item.',
    {'skin': '#F6D7C3', 'hair': '#D8A35D', 'shirt': '#4FC3F7', 'apron': '#FFFFFF', 'accessory': 'cap'},
    most: 1.15,
    opens: 0.75,
    patience: 6,
    step: 0.5,
    clue: '📸 On holiday, happy to spend',
    loves: {'souvenir'},
    lines: {
      'greet': ['Oh wow, a {item}! Would you take {offer}?', 'Hello! This {item} is lovely. {offer}, maybe?'],
      'raise': ['Hmm, {ask} is a bit much. How about {offer}?', 'Oh, {ask}? Could you do {offer}?'],
      'annoyed': ['{ask}? Oh dear, that seems a lot!', 'Wow, {ask}? Really?'],
      'accept': ['Lovely, {price} it is!', 'Deal! {price}, thank you so much!'],
      'thanks': ['{price}? Perfect, thank you!', 'Oh great, {price}. Thanks!'],
      'happy': ['Aw, thank you! {offer} then?', "You're so kind! {offer}?"],
      'impatient': ['I should get going soon... {offer}?', 'My tour bus leaves soon! {offer}?'],
      'walk': ["I think I'll keep looking. Thanks anyway!", 'Maybe another time. Bye!'],
    },
  ),
  Customer(
    'student',
    'Wei Jie the student',
    'A broke polytechnic student buying a present, with very little money but lots of charm.',
    "Casual Singlish, calls the seller 'boss' or 'uncle/auntie', says 'pls lah', 'student price' and 'shiok'.",
    {'skin': '#EBC2A0', 'hair': '#1B1B1B', 'shirt': '#FFB74D', 'apron': '#5C6BC0', 'accessory': 'headphones'},
    most: 0.95,
    opens: 0.5,
    patience: 6,
    step: 0.3,
    clue: '🎒 A small allowance',
    loves: {'toy'},
    lines: {
      'greet': ['Boss, {item} for my girlfriend. Student price {offer}?', 'Eh boss, {offer} for the {item} can?'],
      'raise': ['{ask}? Pls lah boss. {offer}?', 'Aiyo {ask}, my allowance cannot. {offer}?'],
      'annoyed': ['{ask}?! Boss I student leh!', 'Wah {ask}, can buy one week of lunch!'],
      'accept': ['Shiok! {price}, thanks boss!', 'Okay okay, {price}. Thank you!'],
      'thanks': ['{price}! Steady boss!', 'Shiok, {price}! Thanks!'],
      'happy': ['Hehe thanks boss. {offer} pls?', 'Boss so nice! {offer} can?'],
      'impatient': ['Boss, my class starting. {offer}?', 'Quick lah boss, {offer}?'],
      'walk': ['Sian, cannot afford. Bye boss.', 'Next time when I got money.'],
    },
  ),
  Customer(
    'taitai',
    'Mrs Chua',
    'A well-off auntie in a hurry, who will pay well for quality but hates wasting time.',
    "Brisk and a little posh, says 'darling', 'quickly ah' and 'I don't have all day'.",
    {'skin': '#F3D2B8', 'hair': '#5D4037', 'shirt': '#AD1457', 'apron': '#F8BBD0', 'accessory': 'perm'},
    most: 1.2,
    opens: 0.9,
    patience: 4,
    step: 0.6,
    clue: '💎 Wants the best, money no problem',
    loves: {'premium'},
    lines: {
      'greet': ['Darling, the {item}. {offer}, quickly ah.', '{item}, {offer}? I am in a hurry.'],
      'raise': ['{ask}? Fine, {offer}. Quickly.', 'Hmm, {ask}. I give {offer}, final.'],
      'annoyed': ['{ask}? Darling, please.', '{ask}?! I am not a tourist.'],
      'accept': ['Fine, {price}. Wrap it nicely.', '{price}, done. Next time faster ah.'],
      'thanks': ['{price}, good. Thank you, darling.', 'Okay, {price}. Lovely.'],
      'happy': ['Hm, charming. {offer}?', 'Sweet talker. {offer}.'],
      'impatient': ["Darling, I don't have all day. {offer}.", 'Quickly ah. {offer}.'],
      'walk': ['Too slow. I go elsewhere.', "Forget it, I don't have time."],
    },
  ),
];

double _half(double v) => (v * 2).round() / 2; // prices in 50-cent steps

/// One sale: a customer wants your product.
class Sale {
  Sale(this.product, this.customer, {required int seed}) : _rnd = math.Random(seed) {
    most = _half(product.fair * customer.most * (0.8 + _rnd.nextDouble() * 0.4));
    offer = math.min(most, _half(product.fair * customer.opens));
    patience = customer.patience;
  }
  final Product product;
  final Customer customer;
  final math.Random _rnd;
  late double most; // secret: the most they'll pay
  late double offer; // what they're offering now
  late int patience;
  double? ask; // your last asking price
  int chats = 0;
  bool done = false;
  String result = ''; // sold, walked
  double? price;

  /// You name your price. Returns the customer's reaction: accept, raise, annoyed, walk.
  ///
  /// Close to their own offer, it's a yes. Nearer the most they'd pay, they bargain back ("raise": they come up, but
  /// not all the way); ask the same price again (holding firm) and they give in. More than they'd ever pay: they come
  /// up a little, never past their limit, and asking it again wears out their patience fast.
  String askFor(double x) {
    x = _half(x);
    final again = ask != null && x == ask; // the same price again: you're holding firm
    ask = x;
    if (x <= offer) return _sell(x, 'accept');
    if (x > most * 1.6) {
      patience -= 2;
      return patience <= 0 ? _walk() : 'annoyed';
    }
    if (x <= most) {
      if (again || x <= offer + (most - offer) * 0.35) return _sell(x, 'accept');
      patience -= 1;
      if (patience <= 0) return _walk();
      offer = math.min(x - 0.5, math.max(offer + 0.5, _half(offer + customer.step * (x - offer))));
      return 'raise';
    }
    patience -= again ? 2 : 1;
    if (patience <= 0) return _walk();
    // (a small step towards their own limit, not a leap: asking far too much never fetches their best price)
    offer = math.min(most, math.max(offer + 0.5, _half(offer + customer.step * 0.5 * (most - offer))));
    return 'raise';
  }

  /// You take their offer.
  String take() => _sell(offer, 'thanks');

  /// A friendly word or a small free gift: the first one makes them a bit more generous; more just costs patience.
  String chat() {
    chats++;
    if (chats == 1) {
      most = _half(most * 1.05);
      return 'happy';
    }
    patience -= 1;
    return patience <= 0 ? _walk() : 'impatient';
  }

  String _sell(double x, String event) {
    done = true;
    result = 'sold';
    price = x;
    return event;
  }

  String _walk() {
    done = true;
    result = 'walked';
    return 'walk';
  }

  double get profit => price == null ? 0 : price! - product.cost;

  /// 3 stars: well above the usual price; 2: at least the usual price; 1: any profit.
  int get stars {
    final p = price;
    if (p == null) return 0;
    if (p >= product.fair * 1.2) return 3;
    if (p >= product.fair) return 2;
    return p > product.cost ? 1 : 0;
  }

  /// Price buttons: a little above their offer, the usual price, and a bold one.
  List<double> suggestions() {
    final fair = product.fair;
    final a = _half(math.max(offer + 0.5, offer + (fair - offer) * 0.5));
    return {a, _half(fair), _half(fair * 1.15)}.where((x) => x > offer).toList()..sort();
  }
}

String _fill(String s, Map<String, String> v) {
  for (final e in v.entries) {
    s = s.replaceAll('{${e.key}}', e.value);
  }
  return s;
}

String money2(num v) => v == v.roundToDouble() ? '\$${v.toInt()}' : '\$${v.toStringAsFixed(2)}';

/// The customer's ready-made line for an event.
String customerLine(Sale s, String event, int seed) {
  final pool = s.customer.lines[event] ?? s.customer.lines['raise']!;
  return _fill(pool[math.Random(seed).nextInt(pool.length)], {
    'item': s.product.name,
    'offer': money2(s.offer),
    'ask': s.ask == null ? '' : money2(s.ask!),
    'price': s.price == null ? '' : money2(s.price!),
  });
}

const _briefs = {
  'greet': 'You just walked up to the stall. Make your first offer: {offer}.',
  'raise': 'The seller asked {ask}. That is too much for you, but you go up to {offer}. Say so.',
  'annoyed': 'The seller asked {ask}, which you find outrageous. React, without making a new offer.',
  'accept': 'The seller asked {ask} and you agree to pay {price}. Close the deal happily.',
  'thanks': 'The seller accepted your offer of {price}. Thank them.',
  'happy': 'The seller was friendly to you. Respond warmly and repeat your offer of {offer}.',
  'impatient':
      'The seller keeps chatting instead of naming a price. You are getting impatient: your offer is still {offer}.',
  'walk': 'You give up and walk away without buying. Say goodbye in character.',
};

/// The customer's line from the AI (null: use the ready-made one). Only the prices the code gave may appear.
Future<String?> customerSay(AiClient ai, Sale s, String event, List<Map> history) async {
  if (!ai.enabled) return null;
  final prices = <String, double>{
    if (event != 'walk' && event != 'annoyed') 'offer': s.offer,
    if (s.ask != null && event != 'greet') 'ask': s.ask!,
    if (s.price != null) 'price': s.price!,
  };
  var brief = _briefs[event] ?? '';
  for (final e in prices.entries) {
    brief = brief.replaceAll('{${e.key}}', money2(e.value));
  }
  final system =
      'You are ${s.customer.name}, a customer at a market stall in Singapore. ${s.customer.persona}\n'
      'How you talk: ${s.customer.voice}\n'
      'The seller (the player) is selling a ${s.product.name}.\n'
      'Right now: $brief\n'
      'Rules: reply with only your spoken line, under 25 words, no quotes or name label. The only dollar amounts you '
      'may say are: ${prices.isEmpty ? 'none' : prices.values.map(money2).join(', ')}. No other numbers or prices.';
  final talk = [
    for (final m in history.length > 8 ? history.sublist(history.length - 8) : history)
      '${m['who'] == 'you' ? 'Seller' : s.customer.name}: ${m['text']}',
  ].join('\n');
  final user = 'Conversation so far:\n${talk.isEmpty ? '(none yet)' : talk}\n\nYour line as ${s.customer.name}:';
  for (var attempt = 0; attempt < 2; attempt++) {
    final raw = await ai.chat(system, user, temperature: 0.9);
    if (raw == null) return null;
    final text = pySlice(firstLine(stripChars(raw.trim(), '"')), 220);
    final good = checked(text, prices.values);
    if (good != null && pySplit(good).length <= 40) return good;
  }
  return null;
}
