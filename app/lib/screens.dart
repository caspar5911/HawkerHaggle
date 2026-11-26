import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'account_screens.dart';
import 'accounts.dart' show AccountError;
import 'api.dart';
import 'character.dart';
import 'challenge_link.dart';
import 'extras.dart';
import 'guide.dart';
import 'juice.dart';
import 'music.dart';
import 'reminder.dart';
import 'sfx.dart';
import 'voice.dart';
import 'shop_screen.dart';
import 'web_update.dart';
import 'widgets.dart';

// ======================================================================= market
/// The address the game was opened with (the web version: a friend's challenge link). Swappable for tests.
@visibleForTesting
String Function() startAddress = pageAddress;

class MarketScreen extends StatefulWidget {
  const MarketScreen({super.key, required this.api});
  final Api api;
  @override
  State<MarketScreen> createState() => _MarketScreenState();
}

class _MarketScreenState extends State<MarketScreen> with WidgetsBindingObserver {
  Map<String, dynamic>? _me;
  bool _newVersion = false;
  Map<String, dynamic>? _today;
  Map<String, dynamic>? _challenges;
  List<dynamic> _stalls = [];
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load().then((_) => _checkLink());
    _checkVersion();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _checkVersion();
  }

  /// The web version: a newer one published since this tab opened? (build N from the label "test N")
  Future<void> _checkVersion() async {
    final mine = int.tryParse(RegExp(r'\d+').firstMatch(buildLabel)?.group(0) ?? '') ?? 0;
    final newer = await newerWebVersion(mine);
    if (mounted && newer != _newVersion) setState(() => _newVersion = newer);
  }

  Future<void> _load() async {
    try {
      final r = await Future.wait([widget.api.me(), widget.api.stalls(), widget.api.today(), widget.api.challenges()]);
      if (!mounted) return;
      setState(() {
        _me = r[0];
        _stalls = r[1]['stalls'] as List;
        _legend = r[1]['legendary'] as Map?;
        _today = r[2];
        _challenges = r[3];
        _error = null;
      });
      final jar = await widget.api.jar();
      if (mounted) setState(() => _jar = jar);
      widget.api.refreshReminders().ignore(); // a day played gets no reminder
      if (_me?['named'] != true && !_asking) await _editName(first: true);
      // friends: this week's board (also what the stallholders gossip about)
      final b = await widget.api.board();
      if (mounted && b != null) setState(() => _board = b);
    } on ApiError catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  bool _asking = false;
  Map<String, dynamic>? _board;
  Map<String, dynamic>? _jar;
  bool _linkChecked = false;
  Map? _legend; // today's legendary item (null on an ordinary day)

  String _boardLine() {
    final n = (_board?['items'] as List? ?? const []).length;
    return n == 0 ? "This week's top hagglers: be the first!" : "This week's top hagglers and best prices";
  }

  Future<void> _openBoard() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => BoardScreen(
          api: widget.api,
          stalls: _stalls.cast<Map>(),
          onBeat: (stallId, itemId, target) {
            final stall = _stalls.cast<Map>().where((x) => x['id'] == stallId).firstOrNull;
            final item = (stall?['items'] as List?)?.cast<Map>().where((x) => x['id'] == itemId).firstOrNull;
            if (stall != null && item != null) _open(stall, item, target: target);
          },
        ),
      ),
    );
    _load();
  }

  /// First launch (or a tap on 👋): pick the name the stallholders call you.
  Future<void> _editName({bool first = false}) async {
    _asking = true;
    final name = await askName(context, widget.api, current: '${_me?['name'] ?? ''}', first: first);
    _asking = false;
    if (name != null && mounted) setState(() => _me = {...?_me, 'name': name, 'named': true});
  }

  Future<void> _openChallenges() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ChallengesScreen(
          api: widget.api,
          onPlay: (stallId, surprise) {
            final stall = _stalls.cast<Map>().where((x) => x['id'] == (stallId.isEmpty ? 'mei' : stallId)).firstOrNull;
            if (stall != null) _open(stall, (stall['items'] as List).first as Map, surprise: surprise);
          },
        ),
      ),
    );
    _load();
  }

  void _openById(String stallId, String itemId) {
    final stall = _stalls.cast<Map>().where((x) => x['id'] == stallId).firstOrNull;
    final item = (stall?['items'] as List?)?.cast<Map>().where((x) => x['id'] == itemId).firstOrNull;
    if (stall != null && item != null) _open(stall, item);
  }

  Future<void> _open(Map stall, Map item, {String surprise = '', Map? target, bool challenge = false}) async {
    if (item['legendary'] == true) {
      if (item['sold_out'] == true) {
        _toastMarket("✨ You already got today's legendary ${item['name']}. Another legendary item shows up soon!");
        return;
      }
      challenge = true; // open to everyone today, even at a stall not unlocked yet; no market surprise
    }
    if (stall['locked'] == true && !challenge) {
      final days = (stall['unlock_days'] ?? 0) as num;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            days > 0
                ? '🔒 ${stall['name']} opens on day $days of your Market Month.'
                : '🔒 ${stall['name']} opens at ${stall['unlock_at']} ⭐. Get more stars on the other stalls!',
          ),
        ),
      );
      return;
    }
    await Navigator.of(context).push(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 450),
        pageBuilder: (_, _, _) => HaggleScreen(
          api: widget.api,
          stall: stall,
          item: item,
          surprise: surprise,
          target: target,
          challenge: challenge,
        ),
        transitionsBuilder: (_, a, _, child) => SlideTransition(
          position: Tween(
            begin: const Offset(0, 1),
            end: Offset.zero,
          ).animate(CurvedAnimation(parent: a, curve: Curves.easeOutCubic)),
          child: child,
        ),
      ),
    );
    _load();
  }

  // ---------------------------------------------------------------- tabs
  int _tab = 0;
  static const _tabs = [
    ('market', '🏮', 'Market'),
    ('stall', '🧺', 'My stall'),
    ('friends', '👥', 'Friends'),
    ('me', '📒', 'Me'),
  ];

  /// A goal in the jar you can afford now: a dot on the My stall tab.
  bool get _canBuyGoal {
    final j = _jar;
    if (j == null) return false;
    final saved = (j['jar'] as num).toDouble();
    return (j['goals'] as List).cast<Map>().any((g) => g['owned'] != true && saved >= (g['cost'] as num));
  }

  Widget _tabIcon(int i, {bool selected = false}) => Badge(
    isLabelVisible: i == 1 && _canBuyGoal,
    smallSize: 9,
    backgroundColor: Palette.red,
    child: Text(_tabs[i].$2, style: TextStyle(fontSize: selected ? 24 : 21)),
  );

  void _goTab(int i) {
    if (i == _tab) return;
    setState(() => _tab = i);
  }

  Future<void> _push(Widget screen) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
    _load();
  }

  Widget _header() {
    final (_, emoji, label) = _tabs[_tab];
    return Row(
      children: [
        Text(emoji, style: const TextStyle(fontSize: 30)),
        const SizedBox(width: 8),
        Expanded(
          // one line on any phone: shrinks a little on narrow screens instead of wrapping
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              _tab == 0 ? 'Hawker Haggle' : label,
              maxLines: 1,
              style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w700, color: Palette.ink),
            ),
          ),
        ),
        IconButton(
          tooltip: 'Settings',
          icon: const Icon(Icons.settings_rounded, color: Palette.soft),
          onPressed: () => _push(SettingsScreen(api: widget.api)),
        ),
      ],
    );
  }

  List<Widget> _marketPage() => [
    if (_me?['festival'] is Map) FestivalBanner(f: _me!['festival'] as Map),
    if (_me != null) _Hello(me: _me!, onName: _editName),
    const SizedBox(height: 12),
    if (_legend != null) LegendBanner(l: _legend!, onTap: _openLegend),
    if (_challenges != null) ChallengeStrip(c: _challenges!, onTap: _openChallenges),
    if (_today != null) TodayCard(today: _today!, onItem: _openById),
    if (_error != null) _Oops(message: _error!, retry: _load),
    if (_me == null && _error == null)
      const Padding(
        padding: EdgeInsets.only(top: 80),
        child: Center(child: CircularProgressIndicator()),
      ),
    for (var i = 0; i < _stalls.length; i++)
      _Rise(
        delay: i * 90,
        child: _StallCard(
          stall: _stalls[i] as Map,
          awning: Palette.awnings[i % Palette.awnings.length],
          onItem: _open,
          onProfile: (st) => showStallProfile(context, widget.api, st),
        ),
      ),
  ];

  List<Widget> _stallPage() => [
    const SizedBox(height: 8),
    _Entry(
      key: const ValueKey('shop_open'),
      emoji: '🧺',
      title: 'Your own stall: you sell!',
      line: 'Customers come to you. Sell what you bought for more than you paid.',
      color: const Color(0xFFFDE2D8),
      onTap: () => _push(ShopScreen(api: widget.api)),
    ),
    if (_jar != null)
      JarStrip(
        jar: _jar!,
        onTap: () => _push(JarScreen(api: widget.api)),
      ),
    if (_canBuyGoal)
      const Padding(
        padding: EdgeInsets.only(left: 6, bottom: 10),
        child: Text('🎉 You can afford a goal now: open the jar!', style: TextStyle(color: Palette.soft)),
      ),
  ];

  List<Widget> _friendsPage() => [
    const SizedBox(height: 8),
    if (widget.api.account != null) ...[
      _Entry(
        key: const ValueKey('coop_join'),
        emoji: '👥',
        title: "Join a friend's haggle",
        line: 'Type the code from their screen and haggle together. (To invite, tap 👥 in a haggle.)',
        color: const Color(0xFFEDE7F6),
        onTap: () => joinFriend(context, widget.api, _stalls.cast<Map>()),
      ),
      _Entry(
        key: const ValueKey('board_open'),
        emoji: '🏆',
        title: _boardLine(),
        line:
            "Who got the most stars this week, and the best price on each item. Beat one and the stallholders "
            'will gossip about it.',
        color: const Color(0xFFFFF1C9),
        onTap: _openBoard,
      ),
    ] else
      _Entry(
        key: const ValueKey('friends_login'),
        emoji: '🔑',
        title: 'Play with friends',
        line: "Log in to a market account (in Settings) to join friends' haggles and the weekly best prices.",
        color: const Color(0xFFEDE7F6),
        onTap: () => _push(SettingsScreen(api: widget.api)),
      ),
    _Entry(
      key: const ValueKey('challenge_paste'),
      emoji: '🏃',
      title: 'Got a challenge link?',
      line: 'Paste a friend\'s "Can you beat me?" link to play the same haggle and beat their price.',
      color: const Color(0xFFE3F4EC),
      onTap: _pasteChallenge,
    ),
  ];

  Future<void> _pasteChallenge() async {
    final box = TextEditingController();
    final text = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        backgroundColor: Palette.cream,
        title: const Text('🏃 A friend\'s challenge'),
        content: TextField(
          key: const ValueKey('challenge_field'),
          controller: box,
          autofocus: true,
          maxLines: 3,
          minLines: 1,
          decoration: const InputDecoration(hintText: 'Paste their link (or their whole message)'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancel')),
          TextButton(
            key: const ValueKey('challenge_go'),
            onPressed: () => Navigator.pop(c, box.text),
            child: const Text('Play'),
          ),
        ],
      ),
    );
    // (not disposed here: the dialog's closing animation still uses it)
    if (text == null || text.trim().isEmpty || !mounted) return;
    final c = parseChallenge(text);
    if (c == null) {
      _toastMarket("That doesn't look like a challenge link. Ask your friend to share their deal again.");
      return;
    }
    await _openChallenge(c);
  }

  void _toastMarket(String m) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  /// ✨ Today's legendary item (at a stall that may not be unlocked yet).
  Future<void> _openLegend() async {
    final l = _legend!;
    final stall = _stalls.cast<Map>().where((s) => s['id'] == l['stall']).firstOrNull;
    final item = (stall?['items'] as List?)?.cast<Map>().where((i) => i['legendary'] == true).firstOrNull;
    if (stall != null && item != null) await _open(stall, item);
  }

  /// A friend's challenge: their stall and item, with their price to beat (even at a stall you haven't unlocked yet).
  Future<void> _openChallenge(Challenge c) async {
    final stall = _stalls.cast<Map>().where((s) => s['id'] == c.stall).firstOrNull;
    final item = (stall?['items'] as List?)?.cast<Map>().where((i) => i['id'] == c.item).firstOrNull;
    if (stall == null || item == null) {
      _toastMarket('That challenge is for something this market doesn\'t sell (yet). Update the game and try again.');
      return;
    }
    if (c.price > (item['ask'] as num) * 1.3) {
      _toastMarket("That challenge link looks broken. Ask your friend to share their deal again.");
      return;
    }
    await _open(stall, item, target: {'name': c.name, 'price': c.price}, challenge: true);
  }

  /// The web version opened from a friend's challenge link: play it once the market is ready.
  Future<void> _checkLink() async {
    if (_linkChecked) return;
    _linkChecked = true;
    final c = parseChallenge(startAddress());
    if (c == null) return;
    forgetPageQuery(); // a reload doesn't start it again
    if (mounted && _stalls.isNotEmpty) await _openChallenge(c);
  }

  List<Widget> _mePage() => [
    const SizedBox(height: 8),
    if (_me != null)
      Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: _Hello(me: _me!, onName: _editName),
      ),
    _Entry(
      key: const ValueKey('sticker_book'),
      emoji: '📒',
      title: 'Sticker book',
      line: 'Every sticker you have collected, and the ones still to find.',
      color: const Color(0xFFE6F6EF),
      onTap: () => _push(StickerBookScreen(api: widget.api)),
    ),
    _Entry(
      key: const ValueKey('history'),
      emoji: '📜',
      title: 'Past haggles',
      line: 'Reread your chats and share them as pictures.',
      color: const Color(0xFFFFF1C9),
      onTap: () => _push(HistoryScreen(api: widget.api)),
    ),
    _Entry(
      key: const ValueKey('guide_open'),
      emoji: '📖',
      title: 'Haggling guide',
      line: _me?['tricks'] == null
          ? 'The tricks that work, and how to be a good customer in real life.'
          : '${_me!['tricks']} of ${_me!['tricks_total']} tricks learned. The rest appear once you try them!',
      color: const Color(0xFFFDE8E4),
      onTap: () => _push(HaggleGuideScreen(api: widget.api)),
    ),
    _Entry(
      key: const ValueKey('quotes_open'),
      emoji: '⭐',
      title: 'Quote book',
      line: 'Your favourite lines from the stallholders.',
      color: const Color(0xFFE8F0FF),
      onTap: () => _push(QuoteBookScreen(api: widget.api)),
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 720;
    final list = RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        key: ValueKey('home_${_tabs[_tab].$1}'),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          _header(),
          if (_newVersion)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Bouncy(
                key: const ValueKey('new_version'),
                onTap: reloadPage,
                child: const Pill(text: 'A new version is out: tap to reload', icon: '🆕', color: Palette.gold),
              ),
            ),
          ...switch (_tab) {
            1 => _stallPage(),
            2 => _friendsPage(),
            3 => _mePage(),
            _ => _marketPage(),
          },
        ],
      ),
    );
    return Scaffold(
      body: TileBackground(
        child: SafeArea(
          child: wide
              ? Row(
                  children: [
                    NavigationRail(
                      selectedIndex: _tab,
                      onDestinationSelected: _goTab,
                      labelType: NavigationRailLabelType.all,
                      backgroundColor: Colors.white.withValues(alpha: 0.7),
                      indicatorColor: Palette.gold.withValues(alpha: 0.5),
                      destinations: [
                        for (var i = 0; i < _tabs.length; i++)
                          NavigationRailDestination(
                            icon: KeyedSubtree(key: ValueKey('tab_${_tabs[i].$1}'), child: _tabIcon(i)),
                            selectedIcon: _tabIcon(i, selected: true),
                            label: Text(_tabs[i].$3),
                          ),
                      ],
                    ),
                    Expanded(
                      child: Align(
                        alignment: Alignment.topCenter,
                        child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 760), child: list),
                      ),
                    ),
                  ],
                )
              : list,
        ),
      ),
      bottomNavigationBar: wide
          ? null
          : NavigationBar(
              selectedIndex: _tab,
              onDestinationSelected: _goTab,
              height: 64,
              backgroundColor: Colors.white,
              indicatorColor: Palette.gold.withValues(alpha: 0.5),
              destinations: [
                for (var i = 0; i < _tabs.length; i++)
                  NavigationDestination(
                    key: ValueKey('tab_${_tabs[i].$1}'),
                    icon: _tabIcon(i),
                    selectedIcon: _tabIcon(i, selected: true),
                    label: _tabs[i].$3,
                  ),
              ],
            ),
    );
  }
}

/// A big tappable card on the home tabs: an emoji, a title and a line about it.
class _Entry extends StatelessWidget {
  const _Entry({
    super.key,
    required this.emoji,
    required this.title,
    required this.line,
    required this.color,
    required this.onTap,
  });
  final String emoji, title, line;
  final Color color;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Bouncy(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(18)),
        child: Row(
          children: [
            Text(emoji, style: const TextStyle(fontSize: 28)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: Palette.ink),
                  ),
                  const SizedBox(height: 2),
                  Text(line, style: const TextStyle(color: Palette.soft, fontSize: 13)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: Palette.soft),
          ],
        ),
      ),
    ),
  );
}

class _Hello extends StatelessWidget {
  const _Hello({required this.me, required this.onName});
  final Map<String, dynamic> me;
  final VoidCallback onName;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          GestureDetector(key: const ValueKey('name_chip'), onTap: onName, child: _Chip('👋 ${me['name']} ✏️')),
          _Chip('⭐ ${me['best_stars'] ?? me['stars']}'),
          _Chip('🤝 ${me['deals']} deals'),
          if (((me['streak'] ?? 0) as num) > 0) _Chip('🔥 ${me['streak']} days'),
          _Chip('📒 ${me['stickers'] ?? 0}'),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
    child: Text(
      text,
      style: const TextStyle(fontWeight: FontWeight.w600, color: Palette.ink),
    ),
  );
}

class _Rise extends StatelessWidget {
  const _Rise({required this.child, this.delay = 0});
  final Widget child;
  final int delay;
  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
    tween: Tween(begin: 0, end: 1),
    duration: Duration(milliseconds: 500 + delay),
    curve: Interval(delay / (500 + delay), 1, curve: Curves.easeOutBack),
    builder: (_, t, child) => Opacity(
      opacity: t.clamp(0.0, 1.0),
      child: Transform.translate(offset: Offset(0, 40 * (1 - t)), child: child),
    ),
    child: child,
  );
}

/// ✨ Today's legendary item, at the top of the market.
class LegendBanner extends StatelessWidget {
  const LegendBanner({super.key, required this.l, required this.onTap});
  final Map l;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final sold = l['sold_out'] == true;
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Bouncy(
        key: const ValueKey('legend_banner'),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            gradient: const LinearGradient(colors: [Color(0xFFFFE7A3), Color(0xFFFFF6DA)]),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Palette.gold, width: 2),
          ),
          child: Row(
            children: [
              Text('${l['emoji']}', style: const TextStyle(fontSize: 38)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      sold ? '✨ You got today\'s legendary find!' : '✨ Legendary today only!',
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: Palette.ink),
                    ),
                    Text(
                      sold
                          ? 'The ${l['name']} from ${l['stall_name']} is yours. Another legendary item shows up soon.'
                          : 'A ${l['name']} at ${l['stall_name']}\'s. Harder to haggle for, and gone tomorrow!',
                      style: const TextStyle(color: Palette.ink, height: 1.3),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StallCard extends StatelessWidget {
  const _StallCard({required this.stall, required this.awning, required this.onItem, required this.onProfile});
  final Map stall;
  final List<Color> awning;
  final void Function(Map stall, Map item) onItem;
  final void Function(Map stall) onProfile;

  @override
  Widget build(BuildContext context) {
    final items = stall['items'] as List;
    final locked = stall['locked'] == true;
    final card = Container(
      margin: const EdgeInsets.only(bottom: 18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.10), offset: const Offset(0, 6))],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Awning(colors: awning, height: 38),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 14, 14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                GestureDetector(
                  onTap: locked ? null : () => onProfile(stall),
                  child: Stallholder(look: Map<String, dynamic>.from(stall['look'] as Map), size: 96),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              '${stall['name']}',
                              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: Palette.ink),
                            ),
                          ),
                          const SizedBox(width: 6),
                          if (!locked) Hearts(((stall['hearts'] ?? 0) as num).toInt()),
                        ],
                      ),
                      Text('${stall['stall']} · ${stall['place']}', style: const TextStyle(color: Palette.soft)),
                      const SizedBox(height: 10),
                      for (final it in items)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Bouncy(
                            key: (it as Map)['legendary'] == true ? const ValueKey('legend_item') : null,
                            onTap: () => onItem(stall, it),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                              decoration: BoxDecoration(
                                color: it['legendary'] == true ? const Color(0xFFFFF1C9) : Palette.cream,
                                borderRadius: BorderRadius.circular(14),
                                border: it['legendary'] == true ? Border.all(color: Palette.gold, width: 2) : null,
                              ),
                              child: Row(
                                children: [
                                  Text('${it['emoji']}', style: const TextStyle(fontSize: 24)),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          '${it['name']}',
                                          style: const TextStyle(fontWeight: FontWeight.w600, color: Palette.ink),
                                        ),
                                        Text(
                                          it['legendary'] == true
                                              ? (it['sold_out'] == true
                                                    ? '✨ legendary · yours today!'
                                                    : '✨ legendary · today only · asking ${money(it['ask'] as num)}')
                                              : 'asking ${money(it['ask'] as num)}',
                                          style: const TextStyle(color: Palette.soft, fontSize: 12),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Stars(count: ((it['stars'] ?? 0) as num).toInt(), size: 14, animate: false),
                                ],
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
    if (!locked) return card;
    // a locked stall: greyed out, with how many stars it needs
    return Stack(
      children: [
        Opacity(opacity: 0.45, child: card),
        Positioned.fill(
          child: Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18)),
              child: Text(
                ((stall['unlock_days'] ?? 0) as num) > 0
                    ? '🔒 Opens on day ${stall['unlock_days']}'
                    : '🔒 Opens at ${stall['unlock_at']} ⭐',
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: Palette.ink),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _Oops extends StatelessWidget {
  const _Oops({required this.message, required this.retry});
  final String message;
  final VoidCallback retry;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 40),
    child: Column(
      children: [
        const Text('🙈', style: TextStyle(fontSize: 60)),
        Text(
          message,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 16, color: Palette.ink),
        ),
        const SizedBox(height: 12),
        Bouncy(
          onTap: retry,
          child: const Pill(text: 'Try again', color: Palette.gold),
        ),
      ],
    ),
  );
}

// ======================================================================= haggle
/// A sign you can read in the stallholder's face ("😊 Auntie Mei is warming to you."): a quiet aside under the chat.
class _Tell extends StatelessWidget {
  const _Tell(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.centerLeft,
    child: Container(
      key: ValueKey('tell:$text'),
      margin: const EdgeInsets.only(left: 6, top: 2, bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.75), borderRadius: BorderRadius.circular(12)),
      child: Text(
        text,
        style: const TextStyle(fontSize: 13, fontStyle: FontStyle.italic, color: Palette.soft),
      ),
    ),
  );
}

/// A tag-team combo in co-op: one friend sweet-talked, the other made the offer.
const comboLine = '🤜🤛 COMBO! One of you charmed her, the other made the offer: she softens a little.';

/// 👩 Mum's tip in a guided haggle (in the game only: the stallholder and the AI never see it).
class MumTip extends StatelessWidget {
  const MumTip({super.key, required this.text, required this.onSkip});
  final String text;
  final VoidCallback onSkip;
  @override
  Widget build(BuildContext context) => Container(
    key: const ValueKey('mum_tip'),
    margin: const EdgeInsets.only(top: 4, bottom: 8),
    padding: const EdgeInsets.fromLTRB(12, 10, 8, 4),
    decoration: BoxDecoration(
      color: const Color(0xFFFFF4D6),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: Palette.gold, width: 1.5),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('👩', style: TextStyle(fontSize: 26)),
            const SizedBox(width: 8),
            Expanded(
              child: Text.rich(
                TextSpan(
                  children: [
                    const TextSpan(
                      text: 'Mum: ',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    TextSpan(text: text),
                  ],
                ),
                style: const TextStyle(color: Palette.ink, height: 1.35),
              ),
            ),
          ],
        ),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            key: const ValueKey('mum_skip'),
            onPressed: onSkip,
            child: const Text('No more tips', style: TextStyle(color: Palette.soft, fontSize: 12)),
          ),
        ),
      ],
    ),
  );
}

/// Whispers between two friends in a co-op haggle (the same set the server allows). The stallholder never hears them.
const whispers = {
  'firm': '🧱 Go firm now!',
  'sweet': '😊 Sweet-talk first',
  'wait': '✋ Wait, let me try',
  'deal': '🤝 Take the deal!',
  'walk': '🚶 Walk away!',
  'yours': '👉 Your turn',
};

/// Co-op: your friend's last whisper, and a button to whisper back. One of you reads the stallholder and calls it,
/// the other plays it.
class WhisperBar extends StatelessWidget {
  const WhisperBar({super.key, required this.heard, required this.friend, required this.onSay});
  final String heard; // "Melody: 🧱 Go firm now!", or '' (nothing new)
  final String friend;
  final void Function(String id) onSay;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(12, 4, 12, 6),
    child: Row(
      children: [
        Expanded(
          child: heard.isEmpty
              ? Text(
                  '🤫 Whisper to $friend: the stallholder won\'t hear',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13, color: Palette.soft),
                )
              : Container(
                  key: const ValueKey('whisper_heard'),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(color: const Color(0xFFEDE3FA), borderRadius: BorderRadius.circular(14)),
                  child: Text(
                    '🤫 $heard',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Color(0xFF4B2E83)),
                  ),
                ),
        ),
        const SizedBox(width: 8),
        Bouncy(
          key: const ValueKey('whisper_open'),
          onTap: () => showModalBottomSheet<void>(
            context: context,
            backgroundColor: Palette.cream,
            builder: (c) => SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final e in whispers.entries)
                      Bouncy(
                        key: ValueKey('whisper:${e.key}'),
                        onTap: () {
                          Navigator.pop(c);
                          onSay(e.key);
                        },
                        child: Pill(text: e.value),
                      ),
                  ],
                ),
              ),
            ),
          ),
          child: const Pill(text: 'Whisper', icon: '🤫'),
        ),
      ],
    ),
  );
}

class _Msg {
  _Msg(this.text, this.mine, {this.sparkle = false, this.typed = false});
  final String text;
  final bool mine;
  final bool sparkle;
  final bool typed; // the player typed it (only typed messages can be misunderstood)
  bool flagged = false;
}

class HaggleScreen extends StatefulWidget {
  const HaggleScreen({
    super.key,
    required this.api,
    required this.stall,
    required this.item,
    this.surprise = '',
    this.target,
    this.challenge = false,
  });
  final Api api;
  final Map stall;
  final Map item;
  final String surprise; // the daily challenge's Play button can ask for a market surprise
  final Map? target; // "Beat it" from the friends' board, or a friend's challenge link: {name, price}
  final bool challenge; // a friend's challenge link: any stall (even one not unlocked yet), no market surprise
  @override
  State<HaggleScreen> createState() => _HaggleScreenState();
}

class _HaggleScreenState extends State<HaggleScreen> {
  Map<String, dynamic>? _g;
  final _msgs = <_Msg>[];
  final _scroll = ScrollController();
  final _text = TextEditingController();
  bool _busy = false;
  bool _showResult = false;
  int _react = 0;
  Face _face = Face.happy;
  bool _guessSkipped = false;
  int _jolt = 0; // the counter slam (insulted, rude, refused)
  // live co-op, as the host: a friend plays along from their phone; this phone runs the haggle
  String? _room;
  String _friend = '';
  int _seq = 0;
  Timer? _poll;
  bool _pulling = false;
  final _friendMoves = <Map>[];
  int _turn = 0; // goes up with every answer; a friend's move made on an older turn isn't played
  int _bounced = 0; // friend moves not played because you both moved at once (the friend's phone notices)
  String _aside = ''; // "one at a time lah!" after a clash, until the next answer
  String _whisper = ''; // the friend's last whisper (shown for a while)
  Timer? _whisperTimer;
  bool _dilemmaDone = false;
  Object? _twistAnswered; // the twist already answered (by its haggle state)
  final _savedLines = <String>{};
  final _tune = Music.enter('calm');
  // 👩 Mum's tips (the first haggle ever, or asked for again in Settings)
  bool _combo = false; // a tag-team combo just happened (the COMBO! stamp, for a moment)
  bool? _guided; // decided once, when the screen opens
  bool _wasGuided = false;
  final _tipsSeen = <String>{};
  String? _tip;

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void dispose() {
    Music.leave(_tune);
    _poll?.cancel();
    _whisperTimer?.cancel();
    final room = _room;
    if (room != null) widget.api.coopLeave(room);
    _scroll.dispose();
    _text.dispose();
    super.dispose();
  }

  Future<void> _invite() async {
    if (_room != null) return _showCode();
    try {
      final code = await widget.api.coopCreate('${widget.stall['id']}', '${widget.item['id']}');
      if (!mounted) return;
      setState(() => _room = code);
      _poll = Timer.periodic(const Duration(milliseconds: 1500), (_) => _pull());
      await _showCode();
    } on AccountError catch (e) {
      _toast(e.message);
    }
  }

  Future<void> _showCode() => showDialog<void>(
    context: context,
    builder: (c) => AlertDialog(
      backgroundColor: Palette.cream,
      title: const Text('👥 Play together'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('Your friend opens Hawker Haggle, taps "Join a friend" on the market, and types this code:'),
          const SizedBox(height: 12),
          SelectableText(
            _room ?? '',
            key: const ValueKey('coop_code'),
            style: const TextStyle(fontSize: 36, fontWeight: FontWeight.w800, letterSpacing: 6),
          ),
          const SizedBox(height: 8),
          Text(
            _friend.isEmpty ? 'Waiting for your friend…' : '$_friend is here!',
            style: const TextStyle(color: Palette.soft),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () {
            Clipboard.setData(ClipboardData(text: _room ?? ''));
            Navigator.pop(c);
          },
          child: const Text('Copy code'),
        ),
        TextButton(onPressed: () => Navigator.pop(c), child: const Text('OK')),
      ],
    ),
  );

  /// Check the room: a friend joining or leaving, and their moves (played here, one at a time).
  Future<void> _pull() async {
    final room = _room;
    if (room == null || _pulling) return;
    _pulling = true;
    try {
      final r = await widget.api.coopPull(room, _seq);
      for (final m in (r['messages'] as List).cast<Map>()) {
        _seq = (m['seq'] as num).toInt();
        if (m['type'] == 'joined') {
          setState(() => _friend = '${m['name']}');
          _toast('👥 $_friend joined your haggle!');
          _sendState();
        } else if (m['type'] == 'left') {
          _toast('👥 $_friend left.');
          setState(() => _friend = '');
        } else if (m['type'] == 'move' && m['from'] == 'guest') {
          _friendMoves.add(m);
        } else if (m['type'] == 'whisper' && m['from'] == 'guest' && whispers.containsKey(m['say'])) {
          _heard('$_friend: ${whispers[m['say']]}');
        }
      }
      await _playFriendMoves();
    } on AccountError catch (e) {
      if (e.code == 404) {
        _poll?.cancel();
        if (mounted) setState(() => _room = null);
      }
    } finally {
      _pulling = false;
    }
  }

  Future<void> _playFriendMoves() async {
    while (_friendMoves.isNotEmpty && mounted && !_busy && _g?['done'] != true) {
      final m = _friendMoves.removeAt(0);
      final g = _g!;
      // You both moved at once: theirs was made on a turn that's gone (the suggestions, the price, a deal may all
      // have changed), so it isn't played. Their phone gets the new state and they choose again. (A move with no
      // turn is from an older app: played as before.)
      final at = m['at'];
      if (at is num && at.toInt() != _turn) {
        setState(() {
          _bounced++;
          _aside = '🙉 ${widget.stall['name']}: "Eh, one at a time lah!" ($_friend spoke at the same time.)';
        });
        _sendState();
        continue;
      }
      final pick = (m['pick'] as num?)?.toInt();
      final sug = (g['suggestions'] as List? ?? const []).cast<Map>();
      final said = m['text'] != null
          ? '${m['text']}'
          : pick != null && pick < sug.length
          ? '${sug[pick]['text']}'
          : switch (m['move']) {
              'walk' => '(walks away)',
              'buy' || 'confirm' => 'Deal!',
              'cancel' => 'Wait, let me think first.',
              _ => 'OK lah.',
            };
      await _send(
        pick: pick,
        move: m['move'] as String?,
        text: m['text'] as String?,
        mine: '👥 $_friend: $said',
        friend: _friend,
      );
    }
  }

  /// What the friend's phone shows: the haggle as it is now, and the last part of the chat.
  void _sendState() {
    final room = _room, g = _g;
    if (room == null || g == null || _friend.isEmpty) return;
    final chat = [
      for (final m in _msgs.length > 14 ? _msgs.sublist(_msgs.length - 14) : _msgs)
        {'t': m.text.length > 220 ? m.text.substring(0, 220) : m.text, 'm': m.mine, 's': m.sparkle},
    ];
    final view = {
      for (final k in const [
        'line', 'event', 'ask', 'opening', 'patience', 'mood', 'qty', 'done', 'result', 'deal', 'pending', //
        'stars',
        'saved',
        'surprise',
        'surprise_note',
        'accept_text',
        'walk_text',
        'tells',
        'combo',
        'combos',
        'legendary',
      ])
        k: g[k],
      'turn': _turn,
      'bounced': _bounced,
      'moves': _msgs.where((m) => m.mine).length,
      'suggestions': [
        for (final s in (g['suggestions'] as List? ?? const []).cast<Map>())
          {'text': s['text'], 'move': s['move'], 'price': s['price']},
      ],
    };
    widget.api.coopSend(room, {
      'type': 'state',
      'view': view,
      'chat': chat,
      'host': '${widget.api.account?.username}',
    }).ignore();
  }

  Future<void> _start() async {
    setState(() {
      _busy = true;
      _showResult = false;
      _guessSkipped = false;
      _dilemmaDone = false;
      _msgs.clear();
      _tip = null;
    });
    try {
      if (_guided == null) {
        final me = await widget.api.me();
        _guided = _wasGuided = MumGuide.wanted(haggles: (me['haggles'] as num?)?.toInt() ?? 1);
      } else {
        _guided = _wasGuided = false; // "play again": once is enough
      }
      final g = await widget.api.start(
        widget.stall['id'] as String,
        widget.item['id'] as String,
        widget.challenge ? '' : (widget.surprise.isEmpty ? null : widget.surprise),
        widget.challenge,
      );
      _apply(g);
    } on ApiError catch (e) {
      _toast(e.message);
      if (mounted) setState(() => _busy = false);
    }
  }

  void _apply(Map<String, dynamic> g) {
    if (!mounted) return;
    final before = (_g?['pending'] ?? _g?['ask']) as num?;
    final now = (g['pending'] ?? g['ask']) as num?;
    if (const ['insulted', 'rude', 'refuse'].contains(g['event'])) {
      _jolt++;
      HapticFeedback.mediumImpact();
    } else if (before != null && now != null && now < before && g['done'] != true) {
      HapticFeedback.selectionClick(); // ka-ching: the price came down
      Sfx.play('coin', volume: 0.45);
    }
    if (g['found'] != null) _toast('💡 You found ${widget.stall['name']}\'s soft spot: ${g['found']}!');
    if (g['combo'] == true) {
      HapticFeedback.heavyImpact();
      Sfx.play('star', volume: 0.7);
      _combo = true;
      Timer(const Duration(milliseconds: 1400), () {
        if (mounted) setState(() => _combo = false);
      });
    }
    if (_room != null && _friend.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _sendState();
        if (g['done'] == true && g['result'] == 'deal') {
          widget.api.coopTeamwork().then((s) {
            if (s.isNotEmpty) _toast('New sticker! 👥 Teamwork');
          }).ignore();
        }
        _playFriendMoves();
      });
    }
    if (g['pitch_score'] != null && _g?['pitch_score'] == null) {
      _toast(
        const ['😅 That pitch didn\'t work.', '👍 Not a bad pitch!', '🌟 What a pitch!'][(g['pitch_score'] as num)
            .toInt()],
      );
    }
    setState(() {
      _g = g;
      _busy = false;
      _turn++;
      _aside = '';
      _msgs.add(_Msg(g['line'] as String, false, sparkle: g['ai_line'] == true));
      _face = faceFor(g['event'] as String, (g['mood'] as num).toDouble());
      _react++;
      _tip = null;
      if (_guided == true && _friend.isEmpty) {
        final t = mumTip(
          g,
          moves: _msgs.where((m) => m.mine).length,
          seen: _tipsSeen,
          canTap: (g['suggestions'] as List? ?? const []).isNotEmpty,
        );
        if (t != null) {
          _tipsSeen.add(t.$1);
          _tip = t.$2;
        }
      }
    });
    Sfx.forEvent(g['event'] as String);
    if (g['event'] == 'accept') HapticFeedback.heavyImpact();
    _scrollDown();
    if (g['done'] == true) {
      Timer(const Duration(milliseconds: 900), () {
        if (!mounted) return;
        setState(() => _showResult = true);
        _resultSounds(g);
      });
    }
  }

  void _resultSounds(Map<String, dynamic> g) {
    if (g['result'] == 'deal') {
      Sfx.play('deal');
      for (var i = 0; i < (g['stars'] as num).toInt(); i++) {
        Timer(Duration(milliseconds: 350 + i * 300), () {
          if (mounted) Sfx.play('star', volume: 0.6);
        });
      }
    } else if (g['result'] != 'walked') {
      Sfx.play('aww');
    }
  }

  /// Plays a move. False if it wasn't played (a move is already being answered, e.g. your friend's).
  Future<bool> _send({int? pick, String? move, String? text, required String mine, String? friend}) async {
    final g = _g;
    if (g == null || g['done'] == true) return false;
    if (_busy) {
      if (friend == null && _friend.isNotEmpty) _toast('👥 $_friend is talking: wait for the answer, then try again.');
      return false;
    }
    setState(() {
      _busy = true;
      _msgs.add(_Msg(mine, true, typed: text != null));
    });
    _scrollDown();
    try {
      _apply(await widget.api.move(g['id'] as String, pick: pick, move: move, text: text, friend: friend));
    } on ApiError catch (e) {
      _toast(e.message);
      if (mounted) setState(() => _busy = false);
      _sendState(); // the friend's phone stops waiting
    }
    return true;
  }

  void _heard(String w) {
    HapticFeedback.lightImpact();
    setState(() => _whisper = w);
    _whisperTimer?.cancel();
    _whisperTimer = Timer(const Duration(seconds: 20), () {
      if (mounted) setState(() => _whisper = '');
    });
  }

  void _say(String id) {
    final room = _room;
    if (room == null || _friend.isEmpty) return;
    widget.api.coopSend(room, {'type': 'whisper', 'say': id}).ignore();
    _toast('🤫 You whispered: ${whispers[id]}');
  }

  String _banner(Map<String, dynamic>? g) {
    if (g == null || g['done'] == true) return '';
    final t = widget.target;
    var note = '${g['surprise_note'] ?? ''}';
    if (g['challenge'] == true) note = '💬 ${widget.stall['name']} wants convincing! Type your best pitch.';
    if (g['legendary'] == true && note.isEmpty) {
      note = '✨ Legendary! Only today, and ${widget.stall['name']} knows what it\'s worth.';
    }
    if (t == null) return note;
    final beat = '🏆 Beat ${t['name']}\'s ${money(t['price'] as num)}!';
    return note.isEmpty ? beat : '$beat  $note';
  }

  /// Her last reply answered something the player typed: they can say she got it wrong.
  bool get _canFlag =>
      !_busy && _msgs.length >= 2 && !_msgs.last.mine && _msgs[_msgs.length - 2].mine && _msgs[_msgs.length - 2].typed;

  Future<void> _flag() async {
    final g = _g;
    if (g == null || _msgs.last.flagged) return;
    setState(() => _msgs.last.flagged = true);
    try {
      await widget.api.flag(g['id'] as String);
      _toast('Thanks! We\'ll teach ${widget.stall['name']} to understand that better.');
    } on ApiError catch (e) {
      if (mounted) setState(() => _msgs.last.flagged = false);
      _toast(e.message);
    }
  }

  void _scrollDown() => WidgetsBinding.instance.addPostFrameCallback((_) {
    if (_scroll.hasClients) {
      _scroll.animateTo(
        _scroll.position.maxScrollExtent + 120,
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOut,
      );
    }
  });

  void _toast(String m) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  /// After a "Beat it" haggle: did you beat your friend's price?
  String _beatNote(Map g) {
    final t = widget.target!;
    final theirs = (t['price'] as num).toDouble();
    if (g['result'] != 'deal' || g['deal'] == null) {
      return "🏆 ${t['name']}'s ${money(theirs)} still stands. Try again!";
    }
    final mine = (g['deal'] as num).toDouble();
    if (mine < theirs) return '🏆 You beat ${t['name']}\'s ${money(theirs)}! It shows on the board soon.';
    if (mine == theirs) return "🏆 Same as ${t['name']}'s ${money(theirs)}. So close!";
    return "🏆 ${t['name']}'s ${money(theirs)} still stands. Try again!";
  }

  @override
  Widget build(BuildContext context) {
    final g = _g;
    final look = Map<String, dynamic>.from(widget.stall['look'] as Map);
    return Scaffold(
      resizeToAvoidBottomInset: false, // the typing box floats above the keyboard instead
      body: TileBackground(
        child: Stack(
          children: [
            Column(
              children: [
                Jolt(
                  trigger: _jolt,
                  child: _Scene(
                    stall: widget.stall,
                    item: widget.item,
                    look: look,
                    g: g,
                    face: _face,
                    react: _react,
                    coop: _friend.isEmpty ? (_room == null ? '' : 'Code $_room') : _friend,
                    onInvite: g == null || g['done'] == true ? null : _invite,
                  ),
                ),
                Expanded(
                  child: Stack(
                    children: [
                      ListView(
                        controller: _scroll,
                        // room at the top for the surprise banner, which floats over the chat
                        padding: EdgeInsets.fromLTRB(14, _banner(g).isEmpty ? 10 : 52, 14, 10),
                        children: [
                          for (final m in _msgs)
                            Bubble(key: ObjectKey(m), text: m.text, mine: m.mine, sparkle: m.sparkle),
                          // what you can read in their face after that move
                          if (g != null && !_busy)
                            for (final t in (g['tells'] as List? ?? const [])) _Tell('$t'),
                          if (_aside.isNotEmpty && !_busy) _Tell(_aside),
                          if (g?['combo'] == true && !_busy) const _Tell(comboLine),
                          if (_tip != null && !_busy && g?['done'] != true)
                            MumTip(
                              text: _tip!,
                              onSkip: () => setState(() {
                                _guided = false;
                                _tip = null;
                              }),
                            ),
                          // before the first move: a guess at the fair price (checked when the haggle ends)
                          if (g != null && g['done'] != true && _msgs.length == 1 && !_busy && !_guessSkipped)
                            GuessCard(
                              item: '${widget.item['name']}',
                              guess: g['guess'] as num?,
                              onGuess: (v) async {
                                try {
                                  await widget.api.guess(g['id'] as String, v);
                                  if (mounted) setState(() => _g = {...g, 'guess': v});
                                } on ApiError catch (e) {
                                  _toast(e.message);
                                }
                              },
                              onSkip: () => setState(() => _guessSkipped = true),
                            ),
                          if (_canFlag) _FlagChip(flagged: _msgs.last.flagged, onTap: _flag),
                          if (!_busy && _msgs.isNotEmpty && !_msgs.last.mine)
                            _SaveLineChip(
                              saved: _savedLines.contains(_msgs.last.text),
                              onTap: () async {
                                final line = _msgs.last.text;
                                try {
                                  await widget.api.saveQuote('${widget.stall['id']}', line);
                                  if (mounted) setState(() => _savedLines.add(line));
                                  _toast('⭐ Saved to your quote book');
                                } on ApiError catch (e) {
                                  _toast(e.message);
                                }
                              },
                            ),
                          // a silly twist: a quick choice (it only changes their mood)
                          if (g != null && g['twist'] is Map && !identical(_twistAnswered, g) && g['done'] != true)
                            TwistCard(
                              t: g['twist'] as Map,
                              onChoose: (i) async {
                                setState(() => _twistAnswered = g);
                                try {
                                  final r = await widget.api.answerTwist(g['id'] as String, i);
                                  if (mounted) {
                                    setState(() => _msgs.add(_Msg('($r)', false)));
                                    _scrollDown();
                                  }
                                } on ApiError catch (e) {
                                  _toast(e.message);
                                }
                              },
                            ),
                          // a friend's small trouble: help from your savings jar, or not
                          if (g != null && g['dilemma'] is Map && !_dilemmaDone && g['done'] != true)
                            DilemmaCard(
                              d: g['dilemma'] as Map,
                              onAnswer: (help) async {
                                try {
                                  final note = await widget.api.answerDilemma(g['id'] as String, help: help);
                                  if (mounted) setState(() => _dilemmaDone = true);
                                  if (note.isNotEmpty) _toast(note);
                                } on ApiError catch (e) {
                                  _toast(e.message);
                                }
                              },
                            ),
                          if (_busy) const Typing(),
                        ],
                      ),
                      if (_banner(g).isNotEmpty)
                        Positioned(
                          top: 0,
                          left: 0,
                          right: 0,
                          // a soft fade behind the banner so the chat scrolling underneath doesn't show through
                          child: DecoratedBox(
                            decoration: const BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [Palette.tile, Palette.tile, Color(0x00FDEBCB)],
                                stops: [0, 0.8, 1],
                              ),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: SurpriseBanner(_banner(g), urgent: g?['surprise'] == 'rival'),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                if (g != null && g['done'] != true && _friend.isNotEmpty)
                  WhisperBar(heard: _whisper, friend: _friend, onSay: _say),
                if (g != null && g['done'] != true)
                  _Controls(
                    g: g,
                    busy: _busy,
                    text: _text,
                    send: _send,
                    lastLine: g['line'] as String,
                    who: '${widget.stall['name']}',
                  ),
              ],
            ),
            // the moment a deal closes: DEAL! stamped on the screen, then the result card
            if (g != null && g['done'] == true && g['result'] == 'deal' && !_showResult)
              const Positioned.fill(child: DealStamp(text: 'DEAL!'))
            else if (_combo)
              const Positioned.fill(
                child: DealStamp(key: ValueKey('combo_stamp'), text: 'COMBO!'),
              ),
            if (_showResult && g != null) ...[
              if (g['result'] == 'deal') const Positioned.fill(child: Confetti()),
              _Result(
                api: widget.api,
                g: {
                  ...g,
                  'notes': [
                    if (g['closeness'] != null) g['closeness'],
                    ...(g['notes'] as List? ?? const []),
                    if (widget.target != null) _beatNote(g),
                    if (_wasGuided) mumWellDone(g) else if (g['coach'] != null) '💡 Next time: ${g['coach']}',
                  ],
                },
                stall: widget.stall,
                item: widget.item,
                again: _start,
                back: () => Navigator.of(context).pop(),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Scene extends StatelessWidget {
  const _Scene({
    required this.stall,
    required this.item,
    required this.look,
    required this.g,
    required this.face,
    required this.react,
    this.coop = '',
    this.onInvite,
  });
  final String coop; // "👥 Melody" while a friend plays along
  final VoidCallback? onInvite;
  final Map stall;
  final Map item;
  final Map<String, dynamic> look;
  final Map<String, dynamic>? g;
  final Face face;
  final int react;

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.of(context).padding.top;
    return Container(
      height: 262 + top,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFFFE3B3), Color(0xFFFFF6E5)],
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            top: top,
            left: 0,
            right: 0,
            child: const Awning(colors: [Palette.red, Colors.white], height: 50),
          ),
          // the stallholder behind the counter
          Positioned(
            left: 0,
            right: 0,
            bottom: 52,
            child: Center(
              child: Stallholder(look: look, face: face, reactKey: react, size: 146),
            ),
          ),
          // wooden counter with the item
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: 66,
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFFC98B5A),
                border: const Border(top: BorderSide(color: Color(0xFFA8703F), width: 6)),
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.12), offset: const Offset(0, -2))],
              ),
              child: Center(
                child: TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0.6, end: 1),
                  duration: const Duration(milliseconds: 600),
                  curve: Curves.elasticOut,
                  builder: (_, s, child) => Transform.scale(scale: s, child: child),
                  child: Text(
                    '${item['emoji']}${(g?['qty'] ?? 1) > 1 ? ' ${item['emoji']}' : ''}',
                    style: const TextStyle(fontSize: 38),
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            top: top + 6,
            left: 4,
            child: IconButton(
              icon: const Icon(Icons.arrow_back_rounded, color: Palette.ink, size: 28),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ),
          if (onInvite != null || coop.isNotEmpty)
            Positioned(
              top: top + 10,
              right: 12,
              child: Bouncy(
                key: const ValueKey('coop_invite'),
                onTap: onInvite ?? () {},
                child: Pill(text: coop.isEmpty ? 'Play together' : coop, icon: '👥'),
              ),
            ),
          if (g != null) ...[
            Positioned(
              top: top + 64,
              left: 16,
              child: PatienceBar(value: (g!['patience'] as num).toInt()),
            ),
            Positioned(
              top: top + 58,
              right: 16,
              // while a deal waits for a yes, the tag shows the agreed price
              child: PriceTag(
                ask: (g!['pending'] ?? g!['ask']) as num,
                opening: g!['opening'] as num,
                deal: g!['deal'] as num?,
              ),
            ),
          ],
          Positioned(
            top: top + 118,
            left: 16,
            child: Text(
              '${stall['name']}\n${item['name']}',
              style: const TextStyle(fontWeight: FontWeight.w700, color: Palette.ink, height: 1.2),
            ),
          ),
        ],
      ),
    );
  }
}

class _Controls extends StatelessWidget {
  const _Controls({
    required this.g,
    required this.busy,
    required this.text,
    required this.send,
    required this.lastLine,
    required this.who,
  });
  final Map<String, dynamic> g;
  final String lastLine;
  final String who;
  final bool busy;
  final TextEditingController text;
  final Future<bool> Function({int? pick, String? move, String? text, required String mine}) send;

  @override
  Widget build(BuildContext context) {
    final sugs = g['suggestions'] as List;
    final pending = g['pending'] as num?;
    final icons = {
      'offer': '💰',
      'compliment': '😍',
      'competitor': '👀',
      'bulk': '🛍️',
      'regular': '🙋',
      'smalltalk': '💬',
    };
    return Container(
      padding: EdgeInsets.fromLTRB(12, 10, 12, 10 + MediaQuery.of(context).padding.bottom),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.92),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.08), offset: const Offset(0, -3), blurRadius: 8)],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (pending != null) ...[
            _ConfirmDeal(price: pending, busy: busy, send: send),
            const SizedBox(height: 8),
          ] else if (sugs.isNotEmpty) ...[
            // the suggestions sit in one row you can swipe, so the chat keeps its room
            SizedBox(
              height: 52,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                clipBehavior: Clip.none,
                itemCount: sugs.length,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (_, i) => Center(
                  child: Bouncy(
                    enabled: !busy,
                    onTap: () => send(pick: i, mine: sugs[i]['text'] as String),
                    // hold to make it your own: it goes into the typing box to edit before sending
                    onLongPress: () => _openTypeBox(context, prefill: sugs[i]['text'] as String),
                    child: Pill(
                      text: sugs[i]['text'] as String,
                      icon: icons[sugs[i]['move']] ?? '💬',
                      color: Palette.cream,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
          ],
          Row(
            children: [
              // Typing opens a box in the middle of the screen, above the keyboard, so nothing gets hidden. The 🎤 in it
              // opens the same box listening: what you say goes in, to check before sending.
              Expanded(
                child: Bouncy(
                  enabled: !busy,
                  onTap: () => _openTypeBox(context),
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(14, 7, 7, 7),
                    decoration: BoxDecoration(color: Palette.cream, borderRadius: BorderRadius.circular(20)),
                    child: Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'Say anything…',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: Palette.soft, fontWeight: FontWeight.w500),
                          ),
                        ),
                        Semantics(
                          label: 'Say it out loud',
                          button: true,
                          child: Bouncy(
                            key: const ValueKey('mic'),
                            enabled: !busy,
                            onTap: () {
                              text.clear();
                              _openTypeBox(context, listen: true);
                            },
                            child: Container(
                              width: 36,
                              height: 36,
                              alignment: Alignment.center,
                              decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                              child: const Text('🎤', style: TextStyle(fontSize: 18)),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              if (pending == null) ...[
                const SizedBox(width: 8),
                _OkLahButton(
                  key: ValueKey(g['ask']),
                  ask: g['ask'] as num,
                  busy: busy,
                  onConfirmed: () => send(move: 'buy', mine: g['accept_text'] as String),
                ),
                const SizedBox(width: 8),
                Semantics(
                  label: 'Walk away',
                  button: true,
                  child: Bouncy(
                    key: const ValueKey('walk'),
                    enabled: !busy,
                    onTap: () => send(move: 'walk', mine: g['walk_text'] as String),
                    child: Container(
                      width: 50,
                      height: 50,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.black.withValues(alpha: 0.06), width: 2),
                        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.10), offset: const Offset(0, 4))],
                      ),
                      child: const Text('🚶', style: TextStyle(fontSize: 22)),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _openTypeBox(BuildContext context, {String? prefill, bool listen = false}) async {
    if (prefill != null) {
      text.text = prefill;
      text.selection = TextSelection.collapsed(offset: prefill.length);
    }
    final said = await showGeneralDialog<String>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Close',
      barrierColor: Colors.black.withValues(alpha: 0.35),
      transitionDuration: const Duration(milliseconds: 260),
      pageBuilder: (_, _, _) => _TypeBox(
        text: text,
        lastLine: lastLine,
        who: who,
        ask: g['ask'] as num,
        pending: g['pending'] as num?,
        listen: listen,
      ),
      transitionBuilder: (_, a, _, child) => FadeTransition(
        opacity: a,
        child: ScaleTransition(
          scale: CurvedAnimation(parent: a, curve: Curves.easeOutBack),
          child: child,
        ),
      ),
    );
    final t = said?.trim() ?? '';
    if (t.isEmpty) return;
    text.clear();
    if (!await send(text: t, mine: t)) text.text = t; // not sent (someone else is talking): keep what you typed
  }
}

/// The typing box: floats in the middle of the screen, above the keyboard, with the stallholder's last line
/// so you can see what you're answering.
class _TypeBox extends StatefulWidget {
  const _TypeBox({
    required this.text,
    required this.lastLine,
    required this.who,
    required this.ask,
    required this.pending,
    this.listen = false,
  });
  final TextEditingController text;
  final String lastLine;
  final String who;
  final num ask;
  final num? pending;
  final bool listen; // opened with 🎤: start listening straight away

  @override
  State<_TypeBox> createState() => _TypeBoxState();
}

class _TypeBoxState extends State<_TypeBox> {
  bool _listening = false; // the 🎤 is on (from the tap until it ends)
  bool _live = false; // ...and the phone is really listening: speak now
  String _language = '';
  String _problem = '';
  String _voiced = ''; // what the 🎤 last put in the box
  final _field = FocusNode();
  bool _keyboardTip = false; // the player uses their keyboard's mic: say where it is

  /// 🎤 with "Use my keyboard's mic": the keyboard comes up, and the player taps its mic (the music goes quiet, or
  /// the keyboard would hear the tune).
  void _keyboardMic() {
    Music.hush(true).ignore();
    setState(() => _keyboardTip = true);
    _field.requestFocus();
    SystemChannels.textInput.invokeMethod('TextInput.show');
  }

  TextEditingController get text => widget.text;
  String get lastLine => widget.lastLine;
  String get who => widget.who;
  num get ask => widget.ask;
  num? get pending => widget.pending;

  @override
  void initState() {
    super.initState();
    if (widget.listen && Voice.useKeyboard) {
      _keyboardTip = true; // the keyboard opens (autofocus): its own mic does the listening
      Music.hush(true).ignore();
    } else if (widget.listen) {
      // let the box finish opening first (so the tap isn't heard)
      Timer(const Duration(milliseconds: 280), () => mounted ? _talk() : null);
    }
  }

  @override
  void dispose() {
    Voice.instance.stop(); // never leave the microphone on
    if (_keyboardTip) Music.hush(false).ignore();
    _field.dispose();
    super.dispose();
  }

  /// 🎤: what you say goes into the box (you can still fix it before sending).
  Future<void> _talk() async {
    if (_listening) {
      await Voice.instance.stop();
      return;
    }
    setState(() {
      _listening = true;
      _live = false;
      _problem = '';
    });
    // talking again: says it again if the box only has what the 🎤 heard, else adds to what you typed
    final before = text.text == _voiced ? '' : text.text.trim();
    final ok = await Voice.instance.listen(
      onReady: (language) {
        if (mounted) {
          setState(() {
            _live = true;
            _language = language;
          });
        }
      },
      onWords: (heard) {
        final w = [before, heard].where((x) => x.isNotEmpty).join(' ');
        _voiced = w;
        if (!mounted) return;
        text.text = w;
        text.selection = TextSelection.collapsed(offset: w.length);
      },
      onEnd: (problem) {
        if (mounted) {
          setState(() {
            _listening = false;
            _live = false;
            _problem = problem ?? '';
          });
        }
      },
    );
    if (!ok && mounted) {
      setState(() {
        _listening = false;
        _problem = "Voice typing isn't available here. Allow the microphone, or type instead.";
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final keyboard = MediaQuery.of(context).viewInsets.bottom;
    final ideas = pending != null
        ? ['OK lah, deal!', 'Wait ah, let me think', '${money((pending! * 0.95 * 2).round() / 2)} can?']
        : ['Can cheaper?', '${money(ask * 0.75)} can?', 'I buy every week one!', 'So nice! 😍'];
    void done() => Navigator.of(context).pop(text.text);
    return SafeArea(
      child: AnimatedPadding(
        duration: const Duration(milliseconds: 150),
        padding: EdgeInsets.only(bottom: keyboard),
        child: Center(
          child: Material(
            color: Colors.transparent,
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 18),
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(26),
                boxShadow: [
                  BoxShadow(color: Colors.black.withValues(alpha: 0.15), blurRadius: 18, offset: const Offset(0, 6)),
                ],
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      who,
                      style: const TextStyle(fontWeight: FontWeight.w700, color: Palette.soft, fontSize: 13),
                    ),
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                      decoration: BoxDecoration(color: Palette.cream, borderRadius: BorderRadius.circular(16)),
                      child: Text(lastLine, style: const TextStyle(color: Palette.ink, height: 1.3)),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      key: const ValueKey('reply_field'),
                      controller: text,
                      focusNode: _field,
                      autofocus: !widget.listen || Voice.useKeyboard, // talking: no keyboard in the way
                      maxLength: 300,
                      minLines: 1,
                      maxLines: 4,
                      textCapitalization: TextCapitalization.sentences,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => done(),
                      style: const TextStyle(fontSize: 17, color: Palette.ink),
                      decoration: InputDecoration(
                        hintText: !_listening
                            ? 'Type your reply…'
                            : (_live ? 'Listening… say it like you mean it' : 'Getting ready…'),
                        helperText: _problem.isNotEmpty
                            ? _problem
                            : _keyboardTip && !_listening
                            ? "🎤 Tap the mic on your keyboard to talk (on Gboard it's at the top right)."
                            : (!_listening
                                  ? 'Tip: tap 🎤 to say it, or hold a suggestion to edit it.'
                                  : (_live
                                        ? '🎤 Speak now${_language.isEmpty ? '' : ' ($_language)'}. '
                                              'Pauses are fine: tap ■ when you\'re done.'
                                        : '🎤 Wait for "Speak now"…')),
                        helperMaxLines: 2,
                        counterText: '',
                        filled: true,
                        fillColor: Palette.cream,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(18),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final idea in ideas)
                          Bouncy(
                            onTap: () {
                              text.text = idea;
                              text.selection = TextSelection.collapsed(offset: idea.length);
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(
                                border: Border.all(color: Palette.soft.withValues(alpha: 0.3)),
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: Text(idea, style: const TextStyle(fontSize: 13, color: Palette.ink)),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: Bouncy(
                            onTap: () => Navigator.of(context).pop(),
                            child: const Pill(text: 'Cancel'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Bouncy(
                          key: const ValueKey('mic_box'),
                          onTap: Voice.useKeyboard ? _keyboardMic : _talk,
                          child: Pill(
                            text: _listening ? '■' : '🎤',
                            color: _listening ? Palette.red : Palette.cream,
                            textColor: _listening ? Colors.white : Palette.ink,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Bouncy(
                            onTap: done,
                            child: const Pill(text: 'Send', icon: '📨', color: Palette.teal, textColor: Colors.white),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The small "she misunderstood me" link under her reply.
/// "⭐ Save this line": her last line goes into your quote book.
class _SaveLineChip extends StatelessWidget {
  const _SaveLineChip({required this.saved, required this.onTap});
  final bool saved;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.centerLeft,
    child: Padding(
      padding: const EdgeInsets.only(left: 6, bottom: 6),
      child: Bouncy(
        key: const ValueKey('save_line'),
        enabled: !saved,
        onTap: onTap,
        child: Text(
          saved ? '⭐ Saved' : '☆ Save this line',
          style: TextStyle(fontSize: 12, color: Palette.soft.withValues(alpha: 0.9), fontWeight: FontWeight.w600),
        ),
      ),
    ),
  );
}

class _FlagChip extends StatelessWidget {
  const _FlagChip({required this.flagged, required this.onTap});
  final bool flagged;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.centerLeft,
    child: Padding(
      padding: const EdgeInsets.only(left: 6, bottom: 6),
      child: Bouncy(
        enabled: !flagged,
        onTap: onTap,
        child: Text(
          flagged ? '✓ Reported, thank you' : '🤔 She misunderstood me',
          style: TextStyle(fontSize: 12, color: Palette.soft.withValues(alpha: 0.9), fontWeight: FontWeight.w600),
        ),
      ),
    ),
  );
}

/// "OK lah, $X": the first tap turns the button into "Confirm $X" (with a way back); the second tap buys.
class _OkLahButton extends StatefulWidget {
  const _OkLahButton({super.key, required this.ask, required this.busy, required this.onConfirmed});
  final num ask;
  final bool busy;
  final VoidCallback onConfirmed;
  @override
  State<_OkLahButton> createState() => _OkLahButtonState();
}

class _OkLahButtonState extends State<_OkLahButton> {
  bool _asking = false;
  Timer? _undo;

  @override
  void dispose() {
    _undo?.cancel();
    super.dispose();
  }

  void _tap() {
    if (!_asking) {
      setState(() => _asking = true);
      _undo = Timer(const Duration(seconds: 5), () {
        if (mounted) setState(() => _asking = false); // changed their mind by doing nothing
      });
      return;
    }
    _undo?.cancel();
    setState(() => _asking = false);
    widget.onConfirmed();
  }

  @override
  Widget build(BuildContext context) {
    final price = money(widget.ask);
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 250),
      transitionBuilder: (child, a) => ScaleTransition(
        scale: CurvedAnimation(parent: a, curve: Curves.easeOutBack),
        child: child,
      ),
      child: _asking
          ? Row(
              key: const ValueKey('confirm'),
              mainAxisSize: MainAxisSize.min,
              children: [
                Bouncy(
                  enabled: !widget.busy,
                  onTap: _tap,
                  child: Pill(text: 'Confirm $price', icon: '✅', color: Palette.teal, textColor: Colors.white),
                ),
                const SizedBox(width: 4),
                Bouncy(
                  onTap: () {
                    _undo?.cancel();
                    setState(() => _asking = false);
                  },
                  child: const Pill(text: '✕'),
                ),
              ],
            )
          : Bouncy(
              key: const ValueKey('ok'),
              enabled: !widget.busy,
              onTap: _tap,
              child: Pill(text: 'OK lah, $price', icon: '🤝', color: Palette.green, textColor: Colors.white),
            ),
    );
  }
}

/// "Deal at $X?" The stallholder has agreed; nothing ends until the player says yes.
class _ConfirmDeal extends StatelessWidget {
  const _ConfirmDeal({required this.price, required this.busy, required this.send});
  final num price;
  final bool busy;
  final Future<bool> Function({int? pick, String? move, String? text, required String mine}) send;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.85, end: 1),
      duration: const Duration(milliseconds: 500),
      curve: Curves.elasticOut,
      builder: (_, s, child) => Transform.scale(scale: s, child: child),
      child: Column(
        children: [
          Text(
            'Close the deal at ${money(price)}?',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Palette.ink),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                flex: 3,
                child: Bouncy(
                  enabled: !busy,
                  onTap: () => send(move: 'confirm', mine: 'Deal! ${money(price)}'),
                  child: Pill(
                    text: 'Deal, ${money(price)}!',
                    icon: '🤝',
                    color: Palette.green,
                    textColor: Colors.white,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 2,
                child: Bouncy(
                  enabled: !busy,
                  onTap: () => send(move: 'cancel', mine: 'Wait, let me think first.'),
                  child: const Pill(text: 'Not yet', icon: '✋'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Result extends StatefulWidget {
  const _Result({
    required this.api,
    required this.g,
    required this.stall,
    required this.item,
    required this.again,
    required this.back,
  });
  final Api api;
  final Map<String, dynamic> g;
  final Map stall;
  final Map item;
  final VoidCallback again;
  final VoidCallback back;
  @override
  State<_Result> createState() => _ResultState();
}

class _ResultState extends State<_Result> {
  final _card = GlobalKey();
  List<Map<String, dynamic>> _new = const [];

  @override
  void initState() {
    super.initState();
    stickerDetails(widget.api, widget.g['new_stickers'] as List? ?? const []).then((v) {
      if (mounted) setState(() => _new = v);
    });
  }

  Future<void> _share() async {
    final g = widget.g;
    final saved = ((g['saved'] as num) * 100).round();
    var name = '';
    try {
      name = '${(await widget.api.me())['name'] ?? ''}';
    } catch (_) {}
    // a legendary item is gone tomorrow, so its link would lead nowhere
    final legendary = g['legendary'] == true || widget.item['legendary'] == true;
    final link = legendary
        ? ''
        : challengeLink(
            stall: '${widget.stall['id']}',
            item: '${widget.item['id']}',
            price: g['deal'] as num,
            name: name,
          );
    final text =
        'I got the ${legendary ? '✨ legendary ' : ''}${widget.item['name']} for ${money(g['deal'] as num)} at '
        '${widget.stall['name']}\'s stall${saved > 0 ? ' ($saved% off)' : ''}! ${'⭐' * (g['stars'] as num).toInt()} '
        '${legendary ? 'Only today!' : 'Can you beat me? Try here: $link'} #HawkerHaggle';
    try {
      await shareBrag(text, await capturePng(_card));
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Couldn't share this time.")));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final g = widget.g, item = widget.item;
    final deal = g['result'] == 'deal';
    final title = switch (g['result']) {
      'deal' => 'Deal! 🎉',
      'walked' => 'You walked away 🚶',
      'lost' => 'Auntie Rose got it! 😱',
      _ => 'No sale today 😅',
    };
    final saved = ((g['saved'] as num) * 100).round();
    final unlocked = (g['unlocked'] as List? ?? const []).cast<String>();
    return Positioned.fill(
      child: Container(
        color: Colors.black.withValues(alpha: 0.25),
        alignment: Alignment.center,
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: 1),
          duration: const Duration(milliseconds: 600),
          curve: Curves.elasticOut,
          builder: (_, t, child) => Transform.scale(scale: t, child: child),
          child: Container(
            margin: const EdgeInsets.all(22),
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(28)),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w700, color: Palette.ink),
                  ),
                  const SizedBox(height: 10),
                  Stars(count: (g['stars'] as num).toInt()),
                  const SizedBox(height: 10),
                  if (deal)
                    Text(
                      'You got the ${item['name']} for ${money(g['deal'] as num)}'
                      '${(g['qty'] as num) > 1 ? ' each (2 pcs)' : ''}${saved > 0 ? '\nThat\'s $saved% off! 🥳' : '\nFull price... next time haggle more!'}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 16, color: Palette.ink, height: 1.4),
                    )
                  else
                    Text(
                      g['result'] == 'lost'
                          ? 'Too slow! Next time decide faster when someone else wants it.'
                          : 'Every stallholder has a secret lowest price. Try again!',
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 16, color: Palette.ink),
                    ),
                  if (g['mum'] != null) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(color: Palette.cream, borderRadius: BorderRadius.circular(14)),
                      child: Text('📱 ${g['mum']}', style: const TextStyle(color: Palette.ink, height: 1.3)),
                    ),
                  ],
                  for (final st in _new) ...[
                    const SizedBox(height: 10),
                    TweenAnimationBuilder<double>(
                      tween: Tween(begin: 0.5, end: 1),
                      duration: const Duration(milliseconds: 700),
                      curve: Curves.elasticOut,
                      builder: (_, t, child) => Transform.scale(scale: t, child: child),
                      child: Text(
                        'New sticker! ${st['emoji']} ${st['title']}',
                        style: const TextStyle(fontWeight: FontWeight.w700, color: Palette.teal),
                      ),
                    ),
                  ],
                  for (final n in (g['notes'] as List? ?? const []).cast<String>()) ...[
                    const SizedBox(height: 8),
                    Text(
                      n,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontWeight: FontWeight.w700, color: Palette.ink),
                    ),
                  ],
                  for (final u in unlocked) ...[
                    const SizedBox(height: 10),
                    Text(
                      '🔓 A new stall opened: ${widget.api.stallName(u)}!',
                      style: const TextStyle(fontWeight: FontWeight.w700, color: Palette.ink),
                    ),
                  ],
                  if (deal) ...[
                    const SizedBox(height: 14),
                    // the picture that gets shared
                    RepaintBoundary(
                      key: _card,
                      child: Transform.scale(
                        scale: 0.8,
                        child: BragCard(stall: widget.stall, item: item, g: g),
                      ),
                    ),
                    Bouncy(
                      onTap: _share,
                      child: const Pill(text: 'Share', icon: '📤'),
                    ),
                  ],
                  const SizedBox(height: 8),
                  Bouncy(
                    key: const ValueKey('share_chat'),
                    onTap: () async {
                      final past = await widget.api.history();
                      if (past.isEmpty || !context.mounted) return;
                      await Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => HistoryChatScreen(api: widget.api, id: '${past.first['id']}'),
                        ),
                      );
                    },
                    child: const Pill(text: 'Share the chat as a picture', icon: '📸'),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: Bouncy(
                          onTap: widget.back,
                          child: const Pill(text: 'Market', icon: '🏮'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Bouncy(
                          onTap: widget.again,
                          child: const Pill(text: 'Again!', icon: '🔁', color: Palette.gold),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ======================================================================= settings
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, required this.api});
  final Api api;
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _endpoint = TextEditingController();
  final _model = TextEditingController();
  final _key = TextEditingController();
  bool _showKey = false;
  bool _testing = false;
  String? _testResult;
  int _reports = 0;
  bool _hard = false;
  String _name = '';
  ({bool on, int hour, int minute}) _remind = (on: false, hour: 19, minute: 0);

  @override
  void initState() {
    super.initState();
    _reloadAll();
    Reminder.settings().then((r) {
      if (mounted) setState(() => _remind = r);
    });
  }

  String get _remindAt => '${_remind.hour.toString().padLeft(2, '0')}:${_remind.minute.toString().padLeft(2, '0')}';

  Future<void> _setReminder({bool? on, TimeOfDay? at}) async {
    final want = on ?? _remind.on;
    if (want && on == true && !await Reminder.instance.allow()) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              "Notifications are off for Hawker Haggle. Allow them in your phone's Settings > Apps > Hawker Haggle > "
              'Notifications, then try again.',
            ),
          ),
        );
      }
      return;
    }
    final r = (on: want, hour: at?.hour ?? _remind.hour, minute: at?.minute ?? _remind.minute);
    await Reminder.save(on: r.on, hour: r.hour, minute: r.minute);
    if (mounted) setState(() => _remind = r);
    await widget.api.refreshReminders(); // first: planning clears the old plan
    if (on == true) {
      await Reminder.instance.showNow(
        '🔔 Reminder on!',
        "We'll remind you every day at $_remindAt. See you at the market!",
      );
    }
  }

  /// Logging in or out switches whose progress this is: show its name and settings.
  void _reloadAll() {
    () async {
      await widget.api.ensureDevice();
      final n = await widget.api.reportCount();
      final hard = await widget.api.hard();
      final me = await widget.api.me();
      if (!mounted) return;
      setState(() {
        _hard = hard;
        _name = '${me['name']}';
        _endpoint.text = widget.api.ai.endpoint;
        _model.text = widget.api.ai.model;
        _key.text = widget.api.ai.apiKey;
        _reports = n;
      });
    }();
  }

  @override
  void dispose() {
    _endpoint.dispose();
    _model.dispose();
    _key.dispose();
    super.dispose();
  }

  void _toast(String m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  InputDecoration _box(String hint, {Widget? suffix}) => InputDecoration(
    hintText: hint,
    filled: true,
    fillColor: Colors.white,
    suffixIcon: suffix,
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
  );

  static const _title = TextStyle(fontSize: 20, fontWeight: FontWeight.w700);

  @override
  Widget build(BuildContext context) {
    final api = widget.api;
    return Scaffold(
      appBar: AppBar(title: const Text('Settings'), backgroundColor: Palette.cream),
      backgroundColor: Palette.cream,
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text('About', style: _title),
          const SizedBox(height: 6),
          const Text(
            'Hawker Haggle is a game. Stallholders are made-up characters and the game decides every price. '
            'Everything is kept on this phone, unless you log in to a market account (then your progress is kept on '
            'that market server, so any phone you log in on shows it). No email. If you set an AI below, what you type in chats '
            'is sent to that AI to read and to write the replies in "✨" bubbles.',
            style: TextStyle(height: 1.4),
          ),
          const SizedBox(height: 12),
          ListTile(
            key: const ValueKey('settings_name'),
            contentPadding: EdgeInsets.zero,
            title: const Text('Your name', style: TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Text(_name),
            trailing: const Icon(Icons.edit_rounded, color: Palette.soft),
            onTap: () async {
              final n = await askName(context, api, current: _name);
              if (n != null && mounted) setState(() => _name = n);
            },
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Sound effects', style: TextStyle(fontWeight: FontWeight.w600)),
            value: !Sfx.muted,
            onChanged: (on) async {
              await Sfx.setMuted(!on);
              if (on) Sfx.play('coin');
              setState(() {});
            },
          ),
          SwitchListTile(
            key: const ValueKey('music_switch'),
            contentPadding: EdgeInsets.zero,
            title: const Text('Music', style: TextStyle(fontWeight: FontWeight.w600)),
            subtitle: const Text('A little tune in the background. Off if you play your own music.'),
            value: Music.on,
            onChanged: (on) async {
              await Music.setOn(on);
              setState(() {});
            },
          ),
          if (Music.on)
            Row(
              children: [
                const Icon(Icons.volume_down_rounded, color: Palette.soft),
                Expanded(
                  child: Slider(
                    key: const ValueKey('music_volume'),
                    value: Music.level,
                    divisions: 10,
                    label: '${(Music.level * 100).round()}%',
                    onChanged: (v) {
                      Music.setLevel(v);
                      setState(() {});
                    },
                    onChangeEnd: (v) => Music.setLevel(v, save: true),
                  ),
                ),
                const Icon(Icons.volume_up_rounded, color: Palette.soft),
              ],
            ),
          if (Reminder.supported) ...[
            SwitchListTile(
              key: const ValueKey('reminder_switch'),
              contentPadding: EdgeInsets.zero,
              title: const Text('🔔 Daily reminder', style: TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text(
                _remind.on
                    ? 'Every day at $_remindAt (not on days you already played).'
                    : 'One gentle nudge a day to visit the market.',
              ),
              value: _remind.on,
              onChanged: (on) => _setReminder(on: on),
            ),
            if (_remind.on)
              ListTile(
                key: const ValueKey('reminder_time'),
                contentPadding: EdgeInsets.zero,
                title: const Text('Remind me at'),
                trailing: Text(_remindAt, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                onTap: () async {
                  final t = await showTimePicker(
                    context: context,
                    initialTime: TimeOfDay(hour: _remind.hour, minute: _remind.minute),
                  );
                  if (t != null) await _setReminder(at: t);
                },
              ),
          ],
          SwitchListTile(
            key: const ValueKey('keyboard_mic'),
            contentPadding: EdgeInsets.zero,
            title: const Text("🎤 Use my keyboard's mic", style: TextStyle(fontWeight: FontWeight.w600)),
            subtitle: const Text(
              "The 🎤 opens your keyboard: tap its own mic to talk (Gboard's is at the top right). Some keyboards "
              'hear Singlish better.',
            ),
            value: Voice.useKeyboard,
            onChanged: (on) async {
              await Voice.setUseKeyboard(on);
              setState(() {});
            },
          ),
          ListTile(
            key: const ValueKey('mum_again'),
            contentPadding: EdgeInsets.zero,
            title: const Text("👩 Mum's tips again", style: TextStyle(fontWeight: FontWeight.w600)),
            subtitle: const Text('Mum gives tips in your next haggle, like the first time.'),
            onTap: () {
              MumGuide.again = true;
              ScaffoldMessenger.of(context)
                  .showSnackBar(const SnackBar(content: Text("👩 Mum's tips are on for your next haggle.")));
            },
          ),
          SwitchListTile(
            key: const ValueKey('reduce_motion'),
            contentPadding: EdgeInsets.zero,
            title: const Text('Reduce motion', style: TextStyle(fontWeight: FontWeight.w600)),
            subtitle: const Text('No shaking, bouncing or flying coins.'),
            value: Motion.reduced,
            onChanged: (on) async {
              await Motion.set(on);
              setState(() {});
            },
          ),
          SwitchListTile(
            key: const ValueKey('hard_mode'),
            contentPadding: EdgeInsets.zero,
            title: const Text('Hard mode', style: TextStyle(fontWeight: FontWeight.w600)),
            subtitle: const Text('No suggestions: type everything yourself.'),
            value: _hard,
            onChanged: (on) async {
              await api.setHard(on);
              setState(() => _hard = on);
            },
          ),
          const SizedBox(height: 24),
          const Text('AI (optional)', style: _title),
          const SizedBox(height: 6),
          const Text(
            'Any OpenAI-compatible endpoint: your own model, Ollama, LM Studio, OpenAI, OpenRouter... '
            'Leave the address empty to play in simple mode (taps and ready-made lines, works offline).',
            style: TextStyle(height: 1.4, color: Palette.soft),
          ),
          if (api.hasBuiltInAi) ...[
            const SizedBox(height: 10),
            Bouncy(
              onTap: () async {
                await api.useBuiltInAi();
                if (!mounted) return;
                setState(() {
                  _endpoint.text = api.ai.endpoint;
                  _model.text = api.ai.model;
                  _key.text = '';
                  _testResult = null;
                });
                _toast('Default AI set. Tap Test to check it.');
              },
              child: const Pill(text: 'Use default AI', icon: '✨', color: Palette.teal, textColor: Colors.white),
            ),
          ],
          const SizedBox(height: 10),
          TextField(
            key: const ValueKey('ai_endpoint'),
            controller: _endpoint,
            keyboardType: TextInputType.url,
            autocorrect: false,
            decoration: _box('Address, e.g. https://example.com/v1'),
          ),
          const SizedBox(height: 8),
          TextField(
            key: const ValueKey('ai_model'),
            controller: _model,
            autocorrect: false,
            decoration: _box('Model name, e.g. gpt-4o-mini'),
          ),
          const SizedBox(height: 8),
          TextField(
            key: const ValueKey('ai_key'),
            controller: _key,
            autocorrect: false,
            obscureText: !_showKey,
            decoration: _box(
              'API key (if your endpoint needs one)',
              suffix: IconButton(
                icon: Icon(_showKey ? Icons.visibility_off_rounded : Icons.visibility_rounded),
                onPressed: () => setState(() => _showKey = !_showKey),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: Bouncy(
                  enabled: !_testing,
                  onTap: () async {
                    setState(() {
                      _testing = true;
                      _testResult = null;
                    });
                    final r = await api.testAi(endpoint: _endpoint.text, model: _model.text, apiKey: _key.text);
                    if (mounted) {
                      setState(() {
                        _testing = false;
                        _testResult = r;
                      });
                    }
                  },
                  child: Pill(text: _testing ? 'Testing…' : 'Test', icon: '🔌'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Bouncy(
                  onTap: () async {
                    await api.setAi(endpoint: _endpoint.text, model: _model.text, apiKey: _key.text);
                    if (!context.mounted) return;
                    _toast(api.ai.enabled ? 'AI saved. Happy haggling!' : 'Simple mode: no AI.');
                    Navigator.of(context).pop();
                  },
                  child: const Pill(text: 'Save', icon: '💾', color: Palette.gold),
                ),
              ),
            ],
          ),
          if (_testResult != null) ...[
            const SizedBox(height: 8),
            Text(
              _testResult!,
              style: const TextStyle(fontWeight: FontWeight.w600, color: Palette.ink),
            ),
          ],
          const SizedBox(height: 28),
          AccountSection(
            api: api,
            onAiChanged: () {
              setState(() => _testResult = null);
              _reloadAll();
            },
          ),
          const SizedBox(height: 28),
          const Text('Your reports', style: _title),
          const SizedBox(height: 6),
          Text(
            _reports == 0
                ? 'When a stallholder misunderstands you, tap "🤔 She misunderstood me". Reports are kept here.'
                : '$_reports report${_reports == 1 ? '' : 's'} saved. Copy them and send them to the game\'s maker '
                      'to help her understand better.',
            style: const TextStyle(height: 1.4),
          ),
          if (_reports > 0) ...[
            const SizedBox(height: 8),
            Bouncy(
              onTap: () async {
                await Clipboard.setData(ClipboardData(text: await api.reportsText()));
                if (context.mounted) _toast('Copied! Paste it into a message.');
              },
              child: const Pill(text: 'Copy reports', icon: '📋'),
            ),
          ],
          const SizedBox(height: 28),
          Bouncy(
            onTap: () async {
              final ok = await showDialog<bool>(
                context: context,
                builder: (c) => AlertDialog(
                  title: const Text('Delete my data?'),
                  content: Text(
                    api.account != null && !api.account!.admin
                        ? 'Your haggles, stars, player name and reports are removed from this phone and from your account '
                              '${api.account!.username}. Your account and AI settings stay. This cannot be undone.'
                        : 'Your haggles, stars, player name and reports are removed from this phone. Your AI settings stay. '
                              'This cannot be undone.',
                  ),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Keep')),
                    TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Delete')),
                  ],
                ),
              );
              if (ok != true || !context.mounted) return;
              try {
                await api.deleteMe();
                if (context.mounted) {
                  _toast('Deleted. Fresh start!');
                  Navigator.of(context).pop();
                }
              } on ApiError catch (e) {
                if (context.mounted) _toast(e.message);
              }
            },
            child: const Pill(text: 'Delete my data', icon: '🗑️', color: Palette.red, textColor: Colors.white),
          ),
          const SizedBox(height: 28),
          Center(
            child: Text(
              'Version: $buildLabel · ${api.hasBuiltInAi ? 'your build, AI built in' : 'public build'}',
              key: const ValueKey('build_label'),
              style: const TextStyle(color: Palette.soft, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}

/// Live co-op, as the friend: the host's haggle on your phone. Your taps and messages go to the host's phone, which
/// plays them; you see the stallholder answer you both.
class CoopGuestScreen extends StatefulWidget {
  const CoopGuestScreen({super.key, required this.api, required this.code, required this.room, required this.stall});
  final Api api;
  final String code;
  final Map room; // host_name, stall, item
  final Map stall;
  @override
  State<CoopGuestScreen> createState() => _CoopGuestScreenState();
}

class _CoopGuestScreenState extends State<CoopGuestScreen> {
  final _tune = Music.enter('calm');
  Map<String, dynamic>? _g;
  List<Map> _chat = const [];
  final _text = TextEditingController();
  final _scroll = ScrollController();
  Timer? _poll;
  Timer? _wait;
  int _seq = 0;
  bool _busy = false;
  bool _pulling = false;
  bool _ended = false;
  int _react = 0;
  int _bounced = 0; // the host's count of your moves not played (you both moved at once)
  String _aside = '';
  String _whisper = '';
  Timer? _whisperTimer;
  bool _recorded = false; // your share of the haggle is in your own progress
  Map<String, Object?>? _share; // what you got: notes, stickers
  int _typed = 0, _tapped = 0;

  Map get _item =>
      (widget.stall['items'] as List).cast<Map>().firstWhere((i) => i['id'] == widget.room['item'], orElse: () => {});

  @override
  void initState() {
    super.initState();
    _poll = Timer.periodic(const Duration(milliseconds: 1500), (_) => _pull());
    _pull();
  }

  @override
  void dispose() {
    Music.leave(_tune);
    _poll?.cancel();
    _wait?.cancel();
    _whisperTimer?.cancel();
    widget.api.coopLeave(widget.code);
    _text.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _toast(String m) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  Future<void> _pull() async {
    if (_pulling || _ended) return;
    _pulling = true;
    try {
      final r = await widget.api.coopPull(widget.code, _seq);
      for (final m in (r['messages'] as List).cast<Map>()) {
        _seq = (m['seq'] as num).toInt();
        if (m['type'] == 'state' && m['from'] == 'host') _applyState(m);
        if (m['type'] == 'whisper' && m['from'] == 'host' && whispers.containsKey(m['say'])) {
          HapticFeedback.lightImpact();
          setState(() => _whisper = '${widget.room['host_name']}: ${whispers[m['say']]}');
          _whisperTimer?.cancel();
          _whisperTimer = Timer(const Duration(seconds: 20), () {
            if (mounted) setState(() => _whisper = '');
          });
        }
      }
    } on AccountError catch (e) {
      if (e.code == 404 || e.code == 403) {
        _ended = true;
        _poll?.cancel();
        _toast('👥 ${widget.room['host_name']} closed the haggle.');
      }
    } finally {
      _pulling = false;
    }
  }

  void _applyState(Map m) {
    if (!mounted) return;
    final view = Map<String, dynamic>.from(m['view'] as Map);
    final wasDone = _g?['done'] == true;
    final newTurn = view['turn'] != _g?['turn'];
    final bounced = view['bounced'] is num ? (view['bounced'] as num).toInt() : 0;
    final clashed = bounced > _bounced;
    setState(() {
      _g = view;
      _chat = (m['chat'] as List? ?? const []).cast<Map>();
      _busy = false;
      _react++;
      _bounced = bounced;
      if (newTurn) _aside = '';
      if (clashed) {
        _aside = '🙉 ${widget.stall['name']}: "Eh, one at a time lah!" (${widget.room['host_name']} spoke first.)';
      }
    });
    if (clashed) _toast('👥 ${widget.room['host_name']} moved first: have another look, then try again.');
    if (view['combo'] == true && newTurn) {
      HapticFeedback.heavyImpact();
      _toast('🤜🤛 COMBO! You two work well together.');
    }
    Sfx.forEvent('${view['event']}');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent);
    });
    if (!wasDone && view['done'] == true && view['result'] == 'deal') {
      HapticFeedback.heavyImpact();
      Sfx.play('deal');
    }
    if (view['done'] == true && !_recorded) {
      // your share: the haggle goes into your own history, stars, jar and challenges too (once)
      _recorded = true;
      widget.api
          .coopFinish(
            stall: '${widget.stall['id']}',
            item: '${widget.room['item']}',
            view: view,
            host: '${widget.room['host_name']}',
            typed: _typed,
            tapped: _tapped,
          )
          .then((r) {
            if (mounted) setState(() => _share = r);
          })
          .catchError((Object _) {})
          .ignore();
    }
  }

  void _say(String id) {
    widget.api.coopSend(widget.code, {'type': 'whisper', 'say': id}).ignore();
    _toast('🤫 You whispered: ${whispers[id]}');
  }

  Future<bool> _send({int? pick, String? move, String? text, required String mine}) async {
    if (_busy || _g == null || _g!['done'] == true) return false;
    final at = _g!['turn'] is num ? (_g!['turn'] as num).toInt() : null; // the turn you saw (see the host's check)
    if (text != null) {
      _typed++;
    } else if (pick != null) {
      _tapped++;
    }
    setState(() {
      _busy = true;
      _chat = [
        ..._chat,
        {'t': mine, 'm': true, 's': false},
      ];
    });
    try {
      await widget.api.coopSend(widget.code, {'type': 'move', 'pick': ?pick, 'move': ?move, 'text': ?text, 'at': ?at});
      // the host's phone plays it; the answer comes with the next state (or the busy flag clears after a while)
      _wait?.cancel();
      _wait = Timer(const Duration(seconds: 25), () {
        if (mounted && _busy) setState(() => _busy = false);
      });
    } on AccountError catch (e) {
      _toast(e.message);
      if (mounted) setState(() => _busy = false);
      return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final g = _g;
    final look = Map<String, dynamic>.from(widget.stall['look'] as Map);
    return Scaffold(
      resizeToAvoidBottomInset: false,
      body: TileBackground(
        child: Column(
          children: [
            _Scene(
              stall: widget.stall,
              item: _item,
              look: look,
              g: g,
              face: g == null ? Face.happy : faceFor('${g['event']}', ((g['mood'] ?? 0) as num).toDouble()),
              react: _react,
              coop: 'with ${widget.room['host_name']}',
            ),
            Expanded(
              child: ListView(
                controller: _scroll,
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
                children: [
                  if (g == null)
                    Padding(
                      padding: const EdgeInsets.only(top: 30),
                      child: Text(
                        'Joined ${widget.room['host_name']}\'s haggle. Waiting for their phone…',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Palette.soft),
                      ),
                    ),
                  for (final m in _chat) Bubble(text: '${m['t']}', mine: m['m'] == true, sparkle: m['s'] == true),
                  if (g != null && !_busy)
                    for (final t in (g['tells'] as List? ?? const [])) _Tell('$t'),
                  if (_aside.isNotEmpty && !_busy) _Tell(_aside),
                  if (g?['combo'] == true && !_busy) const _Tell(comboLine),
                  if (_busy) const Typing(),
                  if (g != null && g['done'] == true)
                    Container(
                      key: const ValueKey('coop_result'),
                      margin: const EdgeInsets.only(top: 12),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
                      child: Column(
                        children: [
                          Text(
                            g['result'] == 'deal'
                                ? '🤝 Deal at ${money(g['deal'] as num)} together!'
                                : 'No deal this time.',
                            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: Palette.ink),
                          ),
                          if (g['result'] == 'deal' && g['stars'] is num) ...[
                            const SizedBox(height: 6),
                            Text(
                              '⭐' * (g['stars'] as num).toInt(),
                              key: const ValueKey('coop_stars'),
                              style: const TextStyle(fontSize: 24),
                            ),
                          ],
                          for (final n in [
                            ...(_share?['notes'] as List? ?? const []),
                            if (_share?['mum'] != null) _share!['mum'],
                            if ((_share?['stickers'] as List? ?? const []).isNotEmpty)
                              '🏅 New sticker${(_share!['stickers'] as List).length > 1 ? 's' : ''}!',
                          ])
                            Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child: Text(
                                '$n',
                                textAlign: TextAlign.center,
                                style: const TextStyle(color: Palette.soft),
                              ),
                            ),
                          const SizedBox(height: 10),
                          Bouncy(
                            onTap: () => Navigator.of(context).pop(),
                            child: const Pill(text: 'Back to market', icon: '🏮'),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            if (g != null && g['done'] != true)
              WhisperBar(heard: _whisper, friend: '${widget.room['host_name']}', onSay: _say),
            if (g != null && g['done'] != true)
              _Controls(
                g: g,
                busy: _busy,
                text: _text,
                send: _send,
                lastLine: '${g['line']}',
                who: '${widget.stall['name']}',
              ),
          ],
        ),
      ),
    );
  }
}

/// "Join a friend": type the code from your friend's phone.
Future<void> joinFriend(BuildContext context, Api api, List<Map> stalls) async {
  final code = TextEditingController();
  final entered = await showDialog<String>(
    context: context,
    builder: (c) => AlertDialog(
      backgroundColor: Palette.cream,
      title: const Text('👥 Join a friend'),
      content: TextField(
        key: const ValueKey('coop_code_field'),
        controller: code,
        autofocus: true,
        textCapitalization: TextCapitalization.characters,
        maxLength: 5,
        decoration: const InputDecoration(hintText: 'The code on their screen'),
        onSubmitted: (v) => Navigator.pop(c, v),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancel')),
        TextButton(
          key: const ValueKey('coop_join_go'),
          onPressed: () => Navigator.pop(c, code.text),
          child: const Text('Join'),
        ),
      ],
    ),
  );
  code.dispose();
  if (entered == null || entered.trim().isEmpty || !context.mounted) return;
  try {
    final room = await api.coopJoin(entered);
    final stall = stalls.where((s) => s['id'] == room['stall']).firstOrNull;
    if (stall == null || !context.mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CoopGuestScreen(api: api, code: '${room['code']}', room: room, stall: stall),
      ),
    );
  } on AccountError catch (e) {
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
  }
}
