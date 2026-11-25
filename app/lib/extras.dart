// Screens and cards for the game around the haggles: Mum's list, the sticker book, stallholder profiles,
// market-surprise banners, result extras and the brag card to share.
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:share_plus/share_plus.dart';

import 'api.dart';
import 'core/game.dart' show nameMax;
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
    isScrollControlled: true,
    builder: (c) => SafeArea(
      child: SingleChildScrollView(
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
            const SizedBox(height: 6),
            Text(
              p['soft_spot'] != null
                  ? '💡 Soft spot: ${p['soft_spot']}'
                  : '💡 Soft spot: ??? (chat with them to find what they love)',
              key: const ValueKey('soft_spot'),
              style: TextStyle(color: p['soft_spot'] != null ? Palette.ink : Palette.soft, fontWeight: FontWeight.w600),
            ),
            if (p['arc'] case final Map arc) ...[
              const SizedBox(height: 10),
              Text('📖 ${arc['title']}', style: _title),
              const SizedBox(height: 6),
              for (final (i, ch) in (arc['chapters'] as List).cast<Map>().indexed)
                Padding(
                  key: ValueKey('chapter_$i'),
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(
                    switch (ch['state']) {
                      'done' => '✅ ${ch['title']}: ${ch['text']}',
                      'open' => '👉 ${ch['title']}: ${ch['text']}',
                      _ => '🔒 ${ch['title']} (${ch['hearts']} heart${ch['hearts'] == 1 ? '' : 's'})',
                    },
                    style: TextStyle(
                      color: ch['state'] == 'locked' ? Palette.soft : Palette.ink,
                      fontWeight: ch['state'] == 'open' ? FontWeight.w700 : FontWeight.w400,
                      height: 1.35,
                    ),
                  ),
                ),
            ],
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

/// Past haggles: the last 30 finished chats, newest first.
class HistoryScreen extends StatelessWidget {
  const HistoryScreen({super.key, required this.api});
  final Api api;

  static String resultText(Map h) => switch (h['result']) {
    'deal' => 'Bought for ${money(h['deal'] as num)}${((h['qty'] ?? 1) as num) > 1 ? ' each (2)' : ''}',
    'walked' => 'Walked away',
    'lost' => 'Auntie Rose got it',
    _ => 'No sale',
  };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Past haggles'), backgroundColor: Palette.cream),
      backgroundColor: Palette.cream,
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: api.history(),
        builder: (c, snap) {
          final list = snap.data ?? const [];
          if (snap.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
          if (list.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'No haggles yet. Your finished chats will be kept here.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Palette.soft, fontSize: 16),
                ),
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: list.length,
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (_, i) {
              final h = list[i];
              final when = '${h['at']}'.length >= 16 ? '${h['at']}'.substring(0, 16).replaceFirst('T', ' ') : '';
              return Bouncy(
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => HistoryChatScreen(api: api, id: '${h['id']}'),
                  ),
                ),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18)),
                  child: Row(
                    children: [
                      Text('${h['emoji']}', style: const TextStyle(fontSize: 30)),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${h['item_name']} · ${h['stall_name']}',
                              style: const TextStyle(fontWeight: FontWeight.w700, color: Palette.ink),
                            ),
                            Text('${resultText(h)} · $when', style: const TextStyle(color: Palette.soft, fontSize: 13)),
                          ],
                        ),
                      ),
                      if (h['result'] == 'deal') Stars(count: (h['stars'] as num).toInt(), size: 14, animate: false),
                      const Icon(Icons.chevron_right_rounded, color: Palette.soft),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

/// One past haggle's chat, read-only.
class HistoryChatScreen extends StatefulWidget {
  const HistoryChatScreen({super.key, required this.api, required this.id});
  final Api api;
  final String id;
  @override
  State<HistoryChatScreen> createState() => _HistoryChatScreenState();
}

/// A past haggle's chat. Tap lines to pick them (the last four to start with), then share them as a picture.
class _HistoryChatScreenState extends State<HistoryChatScreen> {
  static const maxLines = 6;
  Map<String, dynamic>? _h;
  final _picked = <int>{};

  @override
  void initState() {
    super.initState();
    widget.api.historyItem(widget.id).then((h) {
      if (!mounted) return;
      final n = (h['chat'] as List).length;
      setState(() {
        _h = h;
        _picked.addAll([
          for (var i = n - 4; i < n; i++)
            if (i >= 0) i,
        ]);
      });
    });
  }

  void _toggle(int i) => setState(() {
    if (!_picked.remove(i)) {
      if (_picked.length >= maxLines) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Up to 6 lines fit on the picture.')));
        return;
      }
      _picked.add(i);
    }
  });

  Future<void> _share() async {
    final h = _h!;
    final chat = (h['chat'] as List).cast<Map>();
    final lines = [for (final i in (_picked.toList()..sort())) chat[i]];
    final key = GlobalKey();
    await showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        backgroundColor: Palette.cream,
        contentPadding: const EdgeInsets.all(12),
        content: SingleChildScrollView(
          child: FittedBox(
            child: RepaintBoundary(
              key: key,
              child: ChatCard(h: h, lines: lines, look: Map<String, dynamic>.from(h['look'] as Map? ?? const {})),
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancel')),
          TextButton(
            key: const ValueKey('chat_share_go'),
            onPressed: () async {
              final png = await capturePng(key);
              if (c.mounted) Navigator.pop(c);
              final text = [
                '${h['stall_name']} · ${h['item_name']}',
                for (final m in lines) '${m['who'] == 'you' ? 'Me' : h['stall_name']}: ${m['text']}',
                '🏮 Hawker Haggle',
              ].join('\n');
              await shareBrag(text, png);
            },
            child: const Text('Share'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final h = _h;
    final chat = h == null ? const <Map>[] : (h['chat'] as List).cast<Map>();
    return Scaffold(
      appBar: AppBar(
        title: Text(h == null ? 'Past haggle' : '${h['item_name']} · ${h['stall_name']}'),
        backgroundColor: Palette.cream,
      ),
      backgroundColor: Palette.cream,
      body: h == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 24),
              children: [
                const Text(
                  'Tap lines to pick them for a picture to share.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Palette.soft, fontSize: 13),
                ),
                const SizedBox(height: 6),
                for (final (i, m) in chat.indexed)
                  GestureDetector(
                    key: ValueKey('line_$i'),
                    behavior: HitTestBehavior.opaque,
                    onTap: () => _toggle(i),
                    child: Container(
                      decoration: BoxDecoration(
                        color: _picked.contains(i) ? Palette.gold.withValues(alpha: 0.25) : Colors.transparent,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Bubble(text: '${m['text']}', mine: m['who'] == 'you', sparkle: m['ai'] == true),
                    ),
                  ),
                const SizedBox(height: 12),
                Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
                    child: Text(
                      HistoryScreen.resultText(h),
                      style: const TextStyle(fontWeight: FontWeight.w700, color: Palette.ink),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Center(
                  child: Bouncy(
                    key: const ValueKey('chat_share'),
                    enabled: _picked.isNotEmpty,
                    onTap: _share,
                    child: Pill(text: 'Share as a picture (${_picked.length})', icon: '📸', color: Palette.gold),
                  ),
                ),
              ],
            ),
    );
  }
}

/// One line on the market: today's challenge and your rank. Tap for the Challenges screen.
class ChallengeStrip extends StatelessWidget {
  const ChallengeStrip({super.key, required this.c, required this.onTap});
  final Map<String, dynamic> c;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final d = c['daily'] as Map;
    final r = c['rank'] as Map;
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Bouncy(
        key: const ValueKey('challenge_strip'),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(color: const Color(0xFFE6F4F1), borderRadius: BorderRadius.circular(16)),
          child: Row(
            children: [
              Text(d['done'] == true ? '✅' : '🎯', style: const TextStyle(fontSize: 20)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Today: ${d['title']}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700, color: Palette.ink),
                ),
              ),
              Text(
                'Lv ${r['level']}',
                style: const TextStyle(fontWeight: FontWeight.w700, color: Palette.teal),
              ),
              const Icon(Icons.chevron_right_rounded, color: Palette.soft),
            ],
          ),
        ),
      ),
    );
  }
}

/// Today's challenge, this week's quests, rank, and the Market Month.
class ChallengesScreen extends StatefulWidget {
  const ChallengesScreen({super.key, required this.api, required this.onPlay});
  final Api api;
  final void Function(String stall, String surprise) onPlay;
  @override
  State<ChallengesScreen> createState() => _ChallengesScreenState();
}

class _ChallengesScreenState extends State<ChallengesScreen> {
  Map<String, dynamic>? _c;

  @override
  void initState() {
    super.initState();
    widget.api.challenges().then((c) {
      if (mounted) setState(() => _c = c);
    });
  }

  Widget _card({required Widget child}) => Container(
    margin: const EdgeInsets.only(bottom: 14),
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
    child: child,
  );

  Widget _bar(double v, {Color color = Palette.teal}) => ClipRRect(
    borderRadius: BorderRadius.circular(8),
    child: LinearProgressIndicator(
      value: v.clamp(0, 1),
      minHeight: 10,
      backgroundColor: Palette.cream,
      valueColor: AlwaysStoppedAnimation(color),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final c = _c;
    return Scaffold(
      appBar: AppBar(title: const Text('Challenges'), backgroundColor: Palette.cream),
      backgroundColor: Palette.cream,
      body: c == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // rank
                _card(
                  child: Builder(
                    builder: (_) {
                      final r = c['rank'] as Map;
                      final from = (r['from'] as num).toDouble(), xp = (r['xp'] as num).toDouble();
                      final next = (r['next'] as num?)?.toDouble();
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Level ${r['level']} · ${r['title']}', style: _title),
                          const SizedBox(height: 8),
                          _bar(next == null ? 1 : (xp - from) / (next - from)),
                          const SizedBox(height: 4),
                          Text(
                            next == null ? '${xp.toInt()} XP · top rank!' : '${xp.toInt()} / ${next.toInt()} XP',
                            style: const TextStyle(color: Palette.soft, fontSize: 12),
                          ),
                        ],
                      );
                    },
                  ),
                ),
                // today
                _card(
                  child: Builder(
                    builder: (_) {
                      final d = c['daily'] as Map;
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(d['done'] == true ? '✅' : '🎯', style: const TextStyle(fontSize: 22)),
                              const SizedBox(width: 8),
                              Expanded(child: Text("Today's challenge: ${d['title']}", style: _title)),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text('${d['how']}', style: const TextStyle(color: Palette.ink, height: 1.3)),
                          const SizedBox(height: 4),
                          Text(
                            d['done'] == true ? 'Done! A new one tomorrow.' : '+60 XP · the same for everyone today',
                            style: const TextStyle(color: Palette.soft, fontSize: 12),
                          ),
                          if (d['done'] != true) ...[
                            const SizedBox(height: 10),
                            Bouncy(
                              key: const ValueKey('daily_play'),
                              onTap: () {
                                Navigator.of(context).pop();
                                widget.onPlay('${d['stall']}', '${d['surprise']}');
                              },
                              child: const Pill(text: 'Play', icon: '▶️', color: Palette.gold),
                            ),
                          ],
                        ],
                      );
                    },
                  ),
                ),
                // this week
                _card(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('📋 This week', style: _title),
                      Text(
                        'New quests every Monday · this week ends ${c['week_ends']}',
                        style: const TextStyle(color: Palette.soft, fontSize: 12),
                      ),
                      const SizedBox(height: 10),
                      for (final q in (c['quests'] as List).cast<Map>()) ...[
                        Row(
                          children: [
                            Text(q['done'] == true ? '✅' : '▫️'),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text('${q['title']}', style: const TextStyle(color: Palette.ink)),
                            ),
                            Text('${q['have']}/${q['target']}', style: const TextStyle(color: Palette.soft)),
                          ],
                        ),
                        const SizedBox(height: 4),
                        _bar((q['have'] as num) / (q['target'] as num), color: Palette.gold),
                        const SizedBox(height: 10),
                      ],
                    ],
                  ),
                ),
                // the month
                _card(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('📅 Market Month · day ${c['days_played']} of 30', style: _title),
                      const Text(
                        'Counts days you play (missing a day never resets it).',
                        style: TextStyle(color: Palette.soft, fontSize: 12),
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 4,
                        runSpacing: 4,
                        children: [
                          for (var day = 1; day <= 30; day++)
                            Container(
                              width: 26,
                              height: 26,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: day <= (c['days_played'] as num) ? Palette.teal : Palette.cream,
                                shape: BoxShape.circle,
                              ),
                              child: Text(
                                '$day',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  color: day <= (c['days_played'] as num) ? Colors.white : Palette.soft,
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      for (final m in (c['month'] as List).cast<Map>())
                        Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Text(
                            '${m['reached'] == true ? '✅' : m['emoji']} Day ${m['day']}: ${m['what']}',
                            style: TextStyle(color: m['reached'] == true ? Palette.soft : Palette.ink),
                          ),
                        ),
                      const SizedBox(height: 6),
                      const Text(
                        'After day 30, daily challenges and weekly quests keep coming.',
                        style: TextStyle(color: Palette.soft, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}

// ---------------------------------------------------------------------------- your name
/// "What should the aunties call you?" On first launch it comes with a random name ready to keep.
/// Returns the saved name, or null if closed without saving.
Future<String?> askName(BuildContext context, Api api, {required String current, bool first = false}) =>
    showDialog<String>(
      context: context,
      barrierDismissible: !first,
      builder: (_) => _NameDialog(api: api, current: current, first: first),
    );

class _NameDialog extends StatefulWidget {
  const _NameDialog({required this.api, required this.current, required this.first});
  final Api api;
  final String current;
  final bool first;
  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
  late final _c = TextEditingController(text: widget.current);
  String? _error;
  bool _saving = false;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final name = await widget.api.setName(_c.text);
      if (mounted) Navigator.of(context).pop(name);
    } on ApiError catch (e) {
      if (mounted) {
        setState(() {
          _error = e.message;
          _saving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: Palette.cream,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      title: Text(
        widget.first ? '👋 Welcome to the market!' : '👋 Your name',
        style: const TextStyle(fontWeight: FontWeight.w700, color: Palette.ink),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'What should the aunties and uncles call you? Your friends at the stalls will remember it.',
            style: TextStyle(height: 1.4, color: Palette.soft),
          ),
          const SizedBox(height: 12),
          TextField(
            key: const ValueKey('name_field'),
            controller: _c,
            autofocus: !widget.first,
            maxLength: nameMax,
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _save(),
            onChanged: (_) => _error == null ? null : setState(() => _error = null),
            decoration: InputDecoration(
              filled: true,
              fillColor: Colors.white,
              errorText: _error,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
              suffixIcon: IconButton(
                key: const ValueKey('name_dice'),
                tooltip: 'Random name',
                icon: const Text('🎲', style: TextStyle(fontSize: 20)),
                onPressed: () async {
                  final n = await widget.api.randomName();
                  if (mounted) {
                    setState(() {
                      _c.text = n;
                      _error = null;
                    });
                  }
                },
              ),
            ),
          ),
        ],
      ),
      actions: [
        if (!widget.first) TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        FilledButton(
          key: const ValueKey('name_save'),
          style: FilledButton.styleFrom(backgroundColor: Palette.teal),
          onPressed: _saving ? null : _save,
          child: Text(widget.first ? "Let's go!" : 'Save'),
        ),
      ],
    );
  }
}

/// Before the first move: "what's a fair price?" The answer comes when the haggle ends.
class GuessCard extends StatefulWidget {
  const GuessCard({super.key, required this.item, required this.guess, required this.onGuess, required this.onSkip});
  final String item;
  final num? guess;
  final Future<void> Function(num) onGuess;
  final VoidCallback onSkip;
  @override
  State<GuessCard> createState() => _GuessCardState();
}

class _GuessCardState extends State<GuessCard> {
  final _text = TextEditingController();

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _go() {
    final v = num.tryParse(_text.text.replaceAll(RegExp(r'[^0-9.]'), ''));
    if (v == null || v <= 0) return;
    FocusManager.instance.primaryFocus?.unfocus();
    widget.onGuess(v);
  }

  @override
  Widget build(BuildContext context) {
    final g = widget.guess;
    return Container(
      key: const ValueKey('guess_card'),
      margin: const EdgeInsets.only(top: 6, bottom: 4),
      padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
      decoration: BoxDecoration(color: const Color(0xFFE6F4F1), borderRadius: BorderRadius.circular(16)),
      child: g != null
          ? Text(
              '🤔 Your guess: ${money(g)}. Let\'s see when the haggle ends!',
              key: const ValueKey('guess_done'),
              style: const TextStyle(color: Palette.ink, fontWeight: FontWeight.w600),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '🤔 Before you start: what\'s a fair price for the ${widget.item}?',
                  style: const TextStyle(color: Palette.ink, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    SizedBox(
                      width: 110,
                      child: TextField(
                        key: const ValueKey('guess_field'),
                        controller: _text,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        onSubmitted: (_) => _go(),
                        decoration: InputDecoration(
                          prefixText: '\$ ',
                          isDense: true,
                          filled: true,
                          fillColor: Colors.white,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    TextButton(key: const ValueKey('guess_go'), onPressed: _go, child: const Text('Guess')),
                    TextButton(
                      key: const ValueKey('guess_skip'),
                      onPressed: widget.onSkip,
                      child: const Text('Skip', style: TextStyle(color: Palette.soft)),
                    ),
                  ],
                ),
              ],
            ),
    );
  }
}

/// On the market during a festival week (real dates).
class FestivalBanner extends StatelessWidget {
  const FestivalBanner({super.key, required this.f});
  final Map f;
  @override
  Widget build(BuildContext context) => Container(
    key: const ValueKey('festival_banner'),
    margin: const EdgeInsets.only(bottom: 10),
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
    decoration: BoxDecoration(
      gradient: const LinearGradient(colors: [Color(0xFFFFD6D6), Color(0xFFFFF1C9)]),
      borderRadius: BorderRadius.circular(16),
    ),
    child: Text(
      '${f['emoji']} ${f['name']} week at the market! Festival days are more common, and there\'s a '
      'sticker for a deal this week.',
      style: const TextStyle(color: Palette.ink, fontWeight: FontWeight.w600, height: 1.3),
    ),
  );
}

/// A picture of a few lines from a haggle, to share.
class ChatCard extends StatelessWidget {
  const ChatCard({super.key, required this.h, required this.lines, required this.look});
  final Map h;
  final List<Map> lines;
  final Map<String, dynamic> look;
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 340,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFFFE3B3), Color(0xFFFFF6E5)],
        ),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Stallholder(look: look, face: Face.happy, size: 54),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${h['stall_name']}',
                      style: const TextStyle(fontWeight: FontWeight.w700, color: Palette.ink, fontSize: 17),
                    ),
                    Text('${h['emoji'] ?? ''} ${h['item_name']}', style: const TextStyle(color: Palette.soft)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          for (final m in lines) _CardBubble(text: '${m['text']}', mine: m['who'] == 'you'),
          const SizedBox(height: 8),
          Text(
            '${HistoryScreen.resultText(h)} · 🏮 Hawker Haggle',
            style: const TextStyle(color: Palette.soft, fontWeight: FontWeight.w600, fontSize: 13),
          ),
        ],
      ),
    );
  }
}

/// A plain chat bubble for the picture (no animation, so the picture is always complete).
class _CardBubble extends StatelessWidget {
  const _CardBubble({required this.text, required this.mine});
  final String text;
  final bool mine;
  @override
  Widget build(BuildContext context) => Align(
    alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
    child: Container(
      constraints: const BoxConstraints(maxWidth: 250),
      margin: const EdgeInsets.symmetric(vertical: 3),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(color: mine ? Palette.teal : Colors.white, borderRadius: BorderRadius.circular(16)),
      child: Text(text, style: TextStyle(color: mine ? Colors.white : Palette.ink, height: 1.3)),
    ),
  );
}

/// This week's best prices among the market's players (from their accounts), with "Beat it" for each item.
class BoardScreen extends StatefulWidget {
  const BoardScreen({super.key, required this.api, required this.stalls, required this.onBeat});
  final Api api;
  final List<Map> stalls;
  final void Function(String stall, String item, Map target) onBeat;
  @override
  State<BoardScreen> createState() => _BoardScreenState();
}

class _BoardScreenState extends State<BoardScreen> {
  Map<String, dynamic>? _b;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    widget.api.board().then((b) {
      if (mounted) setState(() => b == null ? _failed = true : _b = b);
    });
  }

  ({Map stall, Map item})? _find(String stallId, String itemId) {
    final s = widget.stalls.where((x) => x['id'] == stallId).firstOrNull;
    final i = (s?['items'] as List?)?.cast<Map>().where((x) => x['id'] == itemId).firstOrNull;
    return s == null || i == null ? null : (stall: s, item: i);
  }

  @override
  Widget build(BuildContext context) {
    final items = (_b?['items'] as List? ?? const []).cast<Map>();
    return Scaffold(
      appBar: AppBar(title: const Text("🏆 This week's best prices"), backgroundColor: Palette.cream),
      backgroundColor: Palette.cream,
      body: _b == null
          ? Center(
              child: _failed
                  ? const Padding(
                      padding: EdgeInsets.all(24),
                      child: Text("Couldn't reach the market server. Try again later.", textAlign: TextAlign.center),
                    )
                  : const CircularProgressIndicator(),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              children: [
                const Text(
                  'The lowest price each player paid this week (Monday to Sunday), from everyone with an approved '
                  'account on this market. Beat a friend\'s price to take the top spot!',
                  style: TextStyle(color: Palette.soft, height: 1.35),
                ),
                const SizedBox(height: 12),
                if (items.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(top: 40),
                    child: Text(
                      'No deals yet this week. Close one and it shows here!',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontWeight: FontWeight.w600, color: Palette.ink),
                    ),
                  ),
                for (final it in items)
                  if (_find('${it['stall']}', '${it['item']}') case final f?) _row(it, f.stall, f.item),
              ],
            ),
    );
  }

  Widget _row(Map it, Map stall, Map item) {
    final top = (it['top'] as List).cast<Map>();
    final you = it['you'] as Map?;
    final best = top.first;
    return Container(
      key: ValueKey('board_${stall['id']}_${item['id']}'),
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${item['emoji']} ${item['name']} · ${stall['name']}',
            style: const TextStyle(fontWeight: FontWeight.w700, color: Palette.ink),
          ),
          const SizedBox(height: 4),
          for (final (i, x) in top.indexed)
            Text(
              '${const ['🥇', '🥈', '🥉'][i]} ${x['name']}${x['you'] == true ? ' (you)' : ''}  ${money(x['price'] as num)}',
              style: TextStyle(color: Palette.ink, fontWeight: x['you'] == true ? FontWeight.w700 : FontWeight.w400),
            ),
          if (you != null && !top.any((x) => x['you'] == true))
            Text('You: ${money(you['price'] as num)}', style: const TextStyle(color: Palette.soft)),
          const SizedBox(height: 6),
          if (best['you'] == true)
            const Text(
              "👑 You're the best this week!",
              style: TextStyle(color: Palette.teal, fontWeight: FontWeight.w700),
            )
          else
            Bouncy(
              key: ValueKey('beat_${stall['id']}_${item['id']}'),
              onTap: () {
                Navigator.of(context).pop();
                widget.onBeat('${stall['id']}', '${item['id']}', {'name': best['name'], 'price': best['price']});
              },
              child: Pill(
                text: "Beat ${best['name']}'s ${money(best['price'] as num)}",
                icon: '🏃',
                color: Palette.gold,
              ),
            ),
        ],
      ),
    );
  }
}
