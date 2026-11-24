// Screens and cards for the game around the haggles: Mum's list, the sticker book, stallholder profiles,
// market-surprise banners, result extras and the brag card to share.
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:share_plus/share_plus.dart';

import 'api.dart';
import 'character.dart';
import 'widgets.dart';

const _title = TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Palette.ink);

/// Mum's daily shopping list on the market screen.
class TodayCard extends StatelessWidget {
  const TodayCard({super.key, required this.today, required this.onItem});
  final Map<String, dynamic> today;
  final void Function(String stall, String item) onItem;

  @override
  Widget build(BuildContext context) {
    final items = (today['items'] as List).cast<Map>();
    final streak = (today['streak'] as num).toInt();
    final done = today['complete'] == true;
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFBF0),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFF2D49B), width: 2),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06), offset: const Offset(0, 4))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('📝', style: TextStyle(fontSize: 22)),
              const SizedBox(width: 6),
              const Expanded(child: Text("Mum's list today", style: _title)),
              if (streak > 0)
                Text(
                  '🔥 $streak',
                  style: const TextStyle(fontWeight: FontWeight.w700, color: Palette.ink),
                ),
            ],
          ),
          const SizedBox(height: 8),
          for (final i in items)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Bouncy(
                enabled: i['done'] != true,
                onTap: () => onItem('${i['stall']}', '${i['item']}'),
                child: Row(
                  children: [
                    Text(i['done'] == true ? '✅' : '⬜', style: const TextStyle(fontSize: 18)),
                    const SizedBox(width: 8),
                    Text('${i['emoji']}', style: const TextStyle(fontSize: 20)),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        '${i['name']}',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: Palette.ink,
                          decoration: i['done'] == true ? TextDecoration.lineThrough : null,
                        ),
                      ),
                    ),
                    if (i['paid'] != null) Text(money(i['paid'] as num), style: const TextStyle(color: Palette.soft)),
                  ],
                ),
              ),
            ),
          Text(
            done
                ? (today['under'] == true
                      ? 'All done, ${money(today['spent'] as num)}: under budget! Mum is proud 🥰'
                      : 'All done, ${money(today['spent'] as num)}: over budget… Mum sighs 😤')
                : 'Budget: ${money(today['budget'] as num)} for both. Spent ${money(today['spent'] as num)} so far.',
            style: const TextStyle(color: Palette.ink, height: 1.3),
          ),
          if ('${today['tip']}'.isNotEmpty && !done) ...[
            const SizedBox(height: 6),
            Text('💡 Mum\'s tip: ${today['tip']}', style: const TextStyle(color: Palette.soft, fontSize: 13)),
          ],
        ],
      ),
    );
  }
}

/// Friendship hearts (0..3).
class Hearts extends StatelessWidget {
  const Hearts(this.n, {super.key, this.size = 14});
  final int n;
  final double size;
  @override
  Widget build(BuildContext context) =>
      Text(List.generate(3, (i) => i < n ? '❤️' : '🤍').join(), style: TextStyle(fontSize: size, letterSpacing: -1));
}

/// A stallholder's profile: hearts and their story so far (tap them on the market).
Future<void> showStallProfile(BuildContext context, Api api, Map stall) async {
  final p = await api.stallProfile('${stall['id']}');
  if (!context.mounted) return;
  final story = (p['story'] as List).cast<String?>();
  final next = p['next_at'] as num?;
  await showModalBottomSheet<void>(
    context: context,
    backgroundColor: Palette.cream,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
    builder: (c) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Stallholder(look: Map<String, dynamic>.from(stall['look'] as Map), size: 80),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${p['name']}', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
                      Hearts((p['hearts'] as num).toInt(), size: 20),
                      Text(
                        next == null ? 'Best friends!' : 'Friendship ${p['points']}/$next to the next heart',
                        style: const TextStyle(color: Palette.soft),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            const Text('Their story', style: _title),
            const SizedBox(height: 6),
            for (final (i, line) in story.indexed)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  line ?? '🔒 ${i + 1} heart${i == 0 ? '' : 's'} to unlock',
                  style: TextStyle(color: line == null ? Palette.soft : Palette.ink, height: 1.35),
                ),
              ),
            const SizedBox(height: 4),
            const Text(
              'Friendship grows with visits and deals, and drops if you are rude.',
              style: TextStyle(color: Palette.soft, fontSize: 12),
            ),
          ],
        ),
      ),
    ),
  );
}

/// The sticker book.
class StickerBookScreen extends StatelessWidget {
  const StickerBookScreen({super.key, required this.api});
  final Api api;
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Sticker book'), backgroundColor: Palette.cream),
      backgroundColor: Palette.cream,
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: api.stickers(),
        builder: (c, snap) {
          final list = snap.data ?? const [];
          final got = list.where((s) => s['earned'] != null).length;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text('$got of ${list.length} collected', style: _title),
              const SizedBox(height: 12),
              GridView.count(
                crossAxisCount: 3,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                childAspectRatio: 0.78,
                children: [
                  for (final s in list)
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: s['earned'] != null ? Colors.white : Colors.white.withValues(alpha: 0.45),
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Opacity(
                            opacity: s['earned'] != null ? 1 : 0.25,
                            child: Text('${s['emoji']}', style: const TextStyle(fontSize: 34)),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${s['title']}',
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12, color: Palette.ink),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            s['earned'] != null ? '${s['earned']}' : '${s['how']}',
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontSize: 10, color: Palette.soft),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

/// The market-surprise banner during a haggle.
class SurpriseBanner extends StatelessWidget {
  const SurpriseBanner(this.text, {super.key, this.urgent = false});
  final String text;
  final bool urgent;
  @override
  Widget build(BuildContext context) {
    if (text.isEmpty) return const SizedBox.shrink();
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      child: Container(
        key: ValueKey(text),
        width: double.infinity,
        margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: urgent ? const Color(0xFFFFE0E0) : const Color(0xFFE6F4F1),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Text(
          text,
          style: const TextStyle(fontWeight: FontWeight.w600, color: Palette.ink),
        ),
      ),
    );
  }
}

/// Names for new stickers on the result card.
Future<List<Map<String, dynamic>>> stickerDetails(Api api, List ids) async {
  if (ids.isEmpty) return const [];
  final all = await api.stickers();
  return [
    for (final s in all)
      if (ids.contains(s['id'])) s,
  ];
}

/// The brag card: a picture of a great deal to share.
class BragCard extends StatelessWidget {
  const BragCard({super.key, required this.stall, required this.item, required this.g});
  final Map stall;
  final Map item;
  final Map<String, dynamic> g;
  @override
  Widget build(BuildContext context) {
    final saved = ((g['saved'] as num) * 100).round();
    final stars = (g['stars'] as num).toInt();
    return Container(
      width: 320,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [Color(0xFFFFE3B3), Color(0xFFFFF6E5)]),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            '🏮 Hawker Haggle',
            style: TextStyle(fontWeight: FontWeight.w700, color: Palette.soft),
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Stallholder(look: Map<String, dynamic>.from(stall['look'] as Map), face: Face.happy, size: 70),
              Text('${item['emoji']}', style: const TextStyle(fontSize: 44)),
            ],
          ),
          Text(
            'I got the ${item['name']} for ${money(g['deal'] as num)}!',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Palette.ink),
          ),
          if (saved > 0) Text('$saved% off ${stall['name']}\'s price', style: const TextStyle(color: Palette.ink)),
          Text(List.generate(3, (i) => i < stars ? '⭐' : '☆').join(' '), style: const TextStyle(fontSize: 22)),
          const SizedBox(height: 4),
          const Text('Can you beat me? 😎', style: TextStyle(color: Palette.soft)),
        ],
      ),
    );
  }
}

/// Share a picture of [key]'s widget (with text as a fallback). The share call is swappable for tests.
Future<void> Function(String text, Uint8List? png) shareBrag = (text, png) async {
  await SharePlus.instance.share(
    ShareParams(
      text: text,
      files: png == null ? null : [XFile.fromData(png, mimeType: 'image/png', name: 'hawker-haggle.png')],
    ),
  );
};

/// Takes the picture for sharing (swappable in tests, where real rendering isn't available).
Future<Uint8List?> Function(GlobalKey key) capturePng = _capturePng;

Future<Uint8List?> _capturePng(GlobalKey key) async {
  try {
    final boundary = key.currentContext?.findRenderObject() as RenderRepaintBoundary?;
    if (boundary == null) return null;
    final image = await boundary.toImage(pixelRatio: 3);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    return data?.buffer.asUint8List();
  } catch (_) {
    return null;
  }
}
