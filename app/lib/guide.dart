/// 👩 Mum's tips in your first haggle: one short tip at the moments that matter (the first offer, her counter, a deal
/// on the table, her last price, when she's cross). Shown in the game only: never sent to the AI or a friend.
library;

class MumGuide {
  MumGuide._();

  /// Off in most widget tests (a new test player has never haggled, so every test would get tips).
  static bool enabled = true;

  /// "Show Mum's tips again" in Settings: the next haggle gets them even after the first.
  static bool again = false;

  /// Should this haggle have tips? (Uses up [again].)
  static bool wanted({required int haggles, bool together = false}) {
    if (!enabled || together) return false;
    if (again) {
      again = false;
      return true;
    }
    return haggles == 0;
  }
}

/// The tip for this moment, as (id, text), or null. [moves] is how many moves the player has made, [seen] the tips
/// already shown in this haggle (each shows once), [canTap] false in Hard mode (no suggestions to tap).
(String, String)? mumTip(Map g, {required int moves, required Set<String> seen, required bool canTap}) {
  if (g['done'] == true) return null;
  final event = '${g['event']}';
  (String, String)? pick(String id, String text) => seen.contains(id) ? null : (id, text);
  if (g['pending'] != null) {
    return pick(
      'pending',
      'She agreed! Tap the green button to buy at this price. Or "Not yet" if you think you can still do better.',
    );
  }
  if (event == 'insulted' || event == 'rude') {
    return pick(
      'cross',
      'Aiyo, she\'s cross! Too low (or too rude) uses up her patience ❤️. Offer a bit closer to her price.',
    );
  }
  if (event == 'final') {
    return pick(
      'final',
      'That\'s her last price. Take it, or walk away 🚶: sometimes they call you back with a better one!',
    );
  }
  if (moves == 0) {
    return pick(
      'start',
      canTap
          ? 'Stallholders always start high. Tap a price below to make an offer: lower saves more, but too low '
                'makes her cross. A 😍 compliment first makes her softer.'
          : 'Stallholders always start high. Type an offer lower than her price, like "\$3 can?". Too low makes '
                'her cross.',
    );
  }
  if (moves >= 1 && !seen.contains('counter')) {
    return pick(
      'counter',
      'She came down! Keep going: each offer a little higher than your last. Watch her patience ❤️ at the top: '
          'when it runs out, she stops selling.',
    );
  }
  if (moves >= 2) {
    return pick(
      'talk',
      'You can also type or say 🎤 anything in your own words. "Auntie, \$3 can or not?" works! The OK lah button '
          'buys at her price.',
    );
  }
  return null;
}

/// Mum's last word on the result card after a guided haggle.
String mumWellDone(Map g) => g['result'] == 'deal'
    ? '👩 Mum: Well done! The more you save, the more ⭐ you get. Try other items, or share your price and let a '
          'friend try to beat it.'
    : '👩 Mum: Never mind, every auntie has a soft spot. Try again: start a bit higher, and keep her patience ❤️ up.';
