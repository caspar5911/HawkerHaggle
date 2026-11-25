/// Festival weeks on real dates (Singapore public holidays, from MOM's gazetted list). During one, festival days
/// at the market are much more common and the stallholders greet you for the festival. Add next years' dates here.
class Festival {
  const Festival(this.id, this.name, this.emoji, this.from, this.to, this.wish);
  final String id; // also the year, so each one's sticker counts once
  final String name;
  final String emoji;
  final String from, to; // yyyy-mm-dd, both days included
  final String wish; // what the AI is told (no numbers)

  Map<String, Object?> toJson() => {'id': id, 'name': name, 'emoji': emoji, 'to': to};
}

const festivals = <Festival>[
  Festival(
    'xmas2026',
    'Christmas',
    '🎄',
    '2026-12-19',
    '2026-12-26',
    "It's Christmas week: the market is decorated and busy. Wish the customer a merry Christmas.",
  ),
  Festival(
    'cny2027',
    'Chinese New Year',
    '🧧',
    '2027-01-30',
    '2027-02-08',
    "It's the week of Chinese New Year: everyone is shopping for the reunion dinner. Wish the customer a happy and prosperous new year (Gong Xi Fa Cai).",
  ),
  Festival(
    'raya2027',
    'Hari Raya Puasa',
    '🌙',
    '2027-03-04',
    '2027-03-11',
    "It's the week of Hari Raya Puasa: the bazaar is busy. Wish the customer Selamat Hari Raya.",
  ),
  Festival(
    'haji2027',
    'Hari Raya Haji',
    '🕌',
    '2027-05-12',
    '2027-05-17',
    "It's the week of Hari Raya Haji. Wish the customer Selamat Hari Raya Haji.",
  ),
  Festival(
    'deepavali2027',
    'Deepavali',
    '🪔',
    '2027-10-22',
    '2027-10-29',
    "It's Deepavali week: the streets are lit up and busy. Wish the customer a happy Deepavali.",
  ),
  Festival(
    'xmas2027',
    'Christmas',
    '🎄',
    '2027-12-19',
    '2027-12-26',
    "It's Christmas week: the market is decorated and busy. Wish the customer a merry Christmas.",
  ),
];

/// The festival week on [day] (yyyy-mm-dd), if any.
Festival? festivalOn(String day) {
  for (final f in festivals) {
    if (day.compareTo(f.from) >= 0 && day.compareTo(f.to) <= 0) return f;
  }
  return null;
}
