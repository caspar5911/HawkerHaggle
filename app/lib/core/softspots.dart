/// Secret soft spots: each stallholder has a subject they love. Mention it in a typed message and they warm up
/// (once per haggle); the first time, it's added to their profile. Kept out of the tips on purpose.
class SoftSpot {
  const SoftSpot(this.topic, this.words);
  final String topic; // shown once found
  final List<String> words; // whole words or phrases that count
  bool heardIn(String text) =>
      words.any((w) => RegExp('\\b${RegExp.escape(w)}\\b', caseSensitive: false).hasMatch(text));
}

const softSpots = <String, SoftSpot>{
  'mei': SoftSpot('mahjong', ['mahjong', 'mah jong', 'mahjongg']),
  'lim': SoftSpot('fishing trips', ['fishing', 'kelong', 'fishing boat', 'went fishing']),
  'raj': SoftSpot('cricket', ['cricket', 'ipl', 'wicket']),
  'siti': SoftSpot('her orchid garden', ['orchid', 'orchids', 'garden', 'gardening']),
  'lee': SoftSpot('Cantonese opera', ['opera', 'cantonese opera', 'chinese opera']),
  'boy': SoftSpot('Formula One', ['f1', 'formula one', 'formula 1', 'grand prix', 'night race']),
  'wong': SoftSpot('old getai songs', ['getai', 'old songs', 'vinyl', 'records', 'teresa teng']),
  'kumar': SoftSpot('old Tamil films', ['tamil film', 'tamil movie', 'tamil movies', 'rajinikanth', 'kollywood']),
  'rosnah': SoftSpot('baking kuih for Hari Raya', ['baking', 'bake', 'kuih', 'pineapple tart', 'pineapple tarts']),
  'faiz': SoftSpot('football', ['football', 'futsal', 'bola', 'premier league', 'lions']),
  'tan': SoftSpot('the old kampung days', ['kampung days', 'old days', 'kampung life', 'olden days']),
};
