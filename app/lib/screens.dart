import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'account_screens.dart';
import 'api.dart';
import 'character.dart';
import 'extras.dart';
import 'sfx.dart';
import 'shop_screen.dart';
import 'web_update.dart';
import 'widgets.dart';

// ======================================================================= market
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
    _load();
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
        _today = r[2];
        _challenges = r[3];
        _error = null;
      });
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

  String _boardLine() {
    final n = (_board?['items'] as List? ?? const []).length;
    return n == 0 ? "This week's best prices: be the first!" : "This week's best prices · beat your friends";
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

  Future<void> _open(Map stall, Map item, {String surprise = '', Map? target}) async {
    if (stall['locked'] == true) {
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
        pageBuilder: (_, _, _) =>
            HaggleScreen(api: widget.api, stall: stall, item: item, surprise: surprise, target: target),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: TileBackground(
        child: SafeArea(
          child: RefreshIndicator(
            onRefresh: _load,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
              children: [
                Row(
                  children: [
                    const Text('🏮', style: TextStyle(fontSize: 30)),
                    const SizedBox(width: 8),
                    const Expanded(
                      // one line on any phone: shrinks a little on narrow screens instead of wrapping
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Hawker Haggle',
                          maxLines: 1,
                          style: TextStyle(fontSize: 30, fontWeight: FontWeight.w700, color: Palette.ink),
                        ),
                      ),
                    ),
                    IconButton(
                      key: const ValueKey('history'),
                      tooltip: 'Past haggles',
                      icon: const Text('📜', style: TextStyle(fontSize: 22)),
                      onPressed: () =>
                          Navigator.of(context).push(MaterialPageRoute(builder: (_) => HistoryScreen(api: widget.api))),
                    ),
                    IconButton(
                      key: const ValueKey('sticker_book'),
                      icon: const Text('📒', style: TextStyle(fontSize: 24)),
                      onPressed: () async {
                        await Navigator.of(context)
                            .push(MaterialPageRoute(builder: (_) => StickerBookScreen(api: widget.api)));
                        _load();
                      },
                    ),
                    IconButton(
                      icon: const Icon(Icons.settings_rounded, color: Palette.soft),
                      onPressed: () async {
                        await Navigator.of(context)
                            .push(MaterialPageRoute(builder: (_) => SettingsScreen(api: widget.api)));
                        _load();
                      },
                    ),
                  ],
                ),
                if (_newVersion)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Bouncy(
                      key: const ValueKey('new_version'),
                      onTap: reloadPage,
                      child: const Pill(text: 'A new version is out: tap to reload', icon: '🆕', color: Palette.gold),
                    ),
                  ),
                if (_me?['festival'] is Map) FestivalBanner(f: _me!['festival'] as Map),
                if (widget.api.account != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Bouncy(
                      key: const ValueKey('board_open'),
                      onTap: _openBoard,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFF1C9),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Row(
                          children: [
                            const Text('🏆', style: TextStyle(fontSize: 20)),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _boardLine(),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontWeight: FontWeight.w700, color: Palette.ink),
                              ),
                            ),
                            const Icon(Icons.chevron_right_rounded, color: Palette.soft),
                          ],
                        ),
                      ),
                    ),
                  ),
                if (_me != null) _Hello(me: _me!, onName: _editName),
                const SizedBox(height: 12),
                if (_challenges != null) ChallengeStrip(c: _challenges!, onTap: _openChallenges),
                if (_me != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 14),
                    child: Bouncy(
                      key: const ValueKey('shop_open'),
                      onTap: () async {
                        await Navigator.of(context)
                            .push(MaterialPageRoute(builder: (_) => ShopScreen(api: widget.api)));
                        _load();
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFDE2D8),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: const Row(
                          children: [
                            Text('🧺', style: TextStyle(fontSize: 20)),
                            SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Run your own stall: sell to tricky customers',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontWeight: FontWeight.w700, color: Palette.ink),
                              ),
                            ),
                            Icon(Icons.chevron_right_rounded, color: Palette.soft),
                          ],
                        ),
                      ),
                    ),
                  ),
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
              ],
            ),
          ),
        ),
      ),
    );
  }
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
                            onTap: () => onItem(stall, it as Map),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                              decoration: BoxDecoration(color: Palette.cream, borderRadius: BorderRadius.circular(14)),
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
                                          'asking ${money(it['ask'] as num)}',
                                          style: const TextStyle(color: Palette.soft, fontSize: 12),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Stars(count: (it['stars'] as num).toInt(), size: 14, animate: false),
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
  });
  final Api api;
  final Map stall;
  final Map item;
  final String surprise; // the daily challenge's Play button can ask for a market surprise
  final Map? target; // "Beat it" from the friends' board: {name, price}
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

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void dispose() {
    _scroll.dispose();
    _text.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    setState(() {
      _busy = true;
      _showResult = false;
      _guessSkipped = false;
      _msgs.clear();
    });
    try {
      final g = await widget.api.start(
        widget.stall['id'] as String,
        widget.item['id'] as String,
        widget.surprise.isEmpty ? null : widget.surprise,
      );
      _apply(g);
    } on ApiError catch (e) {
      _toast(e.message);
      if (mounted) setState(() => _busy = false);
    }
  }

  void _apply(Map<String, dynamic> g) {
    if (!mounted) return;
    setState(() {
      _g = g;
      _busy = false;
      _msgs.add(_Msg(g['line'] as String, false, sparkle: g['ai_line'] == true));
      _face = faceFor(g['event'] as String, (g['mood'] as num).toDouble());
      _react++;
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

  Future<void> _send({int? pick, String? move, String? text, required String mine}) async {
    final g = _g;
    if (g == null || _busy || g['done'] == true) return;
    setState(() {
      _busy = true;
      _msgs.add(_Msg(mine, true, typed: text != null));
    });
    _scrollDown();
    try {
      _apply(await widget.api.move(g['id'] as String, pick: pick, move: move, text: text));
    } on ApiError catch (e) {
      _toast(e.message);
      if (mounted) setState(() => _busy = false);
    }
  }

  String _banner(Map<String, dynamic>? g) {
    if (g == null || g['done'] == true) return '';
    final t = widget.target;
    final note = '${g['surprise_note'] ?? ''}';
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
                _Scene(stall: widget.stall, item: widget.item, look: look, g: g, face: _face, react: _react),
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
            if (_showResult && g != null) ...[
              if (g['result'] == 'deal') const Positioned.fill(child: Confetti()),
              _Result(
                api: widget.api,
                g: widget.target == null
                    ? g
                    : {
                        ...g,
                        'notes': [...(g['notes'] as List? ?? const []), _beatNote(g)],
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
  });
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
  final Future<void> Function({int? pick, String? move, String? text, required String mine}) send;

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
              // Typing opens a box in the middle of the screen, above the keyboard, so nothing gets hidden.
              Expanded(
                child: Bouncy(
                  enabled: !busy,
                  onTap: () => _openTypeBox(context),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                    decoration: BoxDecoration(color: Palette.cream, borderRadius: BorderRadius.circular(20)),
                    child: const Row(
                      children: [
                        Text('✍️', style: TextStyle(fontSize: 18)),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Say anything…',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: Palette.soft, fontWeight: FontWeight.w500),
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

  Future<void> _openTypeBox(BuildContext context, {String? prefill}) async {
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
      pageBuilder: (_, _, _) =>
          _TypeBox(text: text, lastLine: lastLine, who: who, ask: g['ask'] as num, pending: g['pending'] as num?),
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
    send(text: t, mine: t);
  }
}

/// The typing box: floats in the middle of the screen, above the keyboard, with the stallholder's last line
/// so you can see what you're answering.
class _TypeBox extends StatelessWidget {
  const _TypeBox({
    required this.text,
    required this.lastLine,
    required this.who,
    required this.ask,
    required this.pending,
  });
  final TextEditingController text;
  final String lastLine;
  final String who;
  final num ask;
  final num? pending;

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
                      autofocus: true,
                      maxLength: 300,
                      minLines: 1,
                      maxLines: 4,
                      textCapitalization: TextCapitalization.sentences,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => done(),
                      style: const TextStyle(fontSize: 17, color: Palette.ink),
                      decoration: InputDecoration(
                        hintText: 'Type your reply…',
                        helperText: 'Tip: hold a suggestion to bring it here and edit it.',
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
  final Future<void> Function({int? pick, String? move, String? text, required String mine}) send;

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
    final text =
        'I got the ${widget.item['name']} for ${money(g['deal'] as num)} at ${widget.stall['name']}\'s stall'
        '${saved > 0 ? ' ($saved% off)' : ''}! ${'⭐' * (g['stars'] as num).toInt()} Can you beat me? #HawkerHaggle';
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

  @override
  void initState() {
    super.initState();
    _reloadAll();
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
