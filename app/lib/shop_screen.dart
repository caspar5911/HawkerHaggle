// Run your own stall: you sell, customers bargain you down. Tap a price, take their offer, chat, or type a price.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'api.dart';
import 'character.dart';
import 'extras.dart' show InventoryScreen;
import 'music.dart';
import 'sfx.dart';
import 'widgets.dart';

class ShopScreen extends StatefulWidget {
  const ShopScreen({super.key, required this.api});
  final Api api;
  @override
  State<ShopScreen> createState() => _ShopScreenState();
}

class _ShopScreenState extends State<ShopScreen> {
  Map<String, dynamic>? _s;
  final _msgs = <({String text, bool mine, bool sparkle})>[];
  final _scroll = ScrollController();
  final _price = TextEditingController();
  bool _busy = false;
  int _react = 0;
  final _tune = Music.enter('calm');

  @override
  void initState() {
    super.initState();
    _next();
  }

  @override
  void dispose() {
    Music.leave(_tune);
    _scroll.dispose();
    _price.dispose();
    super.dispose();
  }

  void _toast(String m) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  String? _closed; // why no customer can come (nothing to sell): shown instead of the customer

  Future<void> _next() async {
    setState(() {
      _busy = true;
      _msgs.clear();
      _s = null;
      _closed = null;
    });
    try {
      _apply(await widget.api.shopStart());
    } on ApiError catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _closed = e.message;
        });
      }
    }
  }

  void _apply(Map<String, dynamic> s) {
    if (!mounted) return;
    setState(() {
      _s = s;
      _busy = false;
      _msgs.add((text: '${s['line']}', mine: false, sparkle: s['ai_line'] == true));
      _react++;
    });
    if (s['done'] == true) {
      if (s['result'] == 'sold') {
        Sfx.play('deal');
        HapticFeedback.heavyImpact();
      } else {
        Sfx.play('aww');
      }
    } else {
      Sfx.forEvent(s['event'] == 'annoyed' ? 'insulted' : 'counter');
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent + 120,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  /// 👋 "Not today": send this customer away, and the next one comes.
  Future<void> _pass() async {
    final s = _s;
    if (s == null || _busy) return;
    setState(() => _busy = true);
    try {
      await widget.api.shopPass(s['id'] as String);
    } on ApiError catch (e) {
      if (e.code != 404) {
        // (out of "Not today"s: this customer stays)
        _toast(e.message);
        if (mounted) setState(() => _busy = false);
        return;
      }
    }
    if (mounted) await _next();
  }

  Future<void> _move({double? ask, bool take = false, bool chat = false, required String mine}) async {
    final s = _s;
    if (s == null || _busy || s['done'] == true) return;
    setState(() {
      _busy = true;
      _msgs.add((text: mine, mine: true, sparkle: false));
    });
    try {
      _apply(await widget.api.shopMove(s['id'] as String, ask: ask, take: take, chat: chat));
    } on ApiError catch (e) {
      _toast(e.message);
      if (mounted) setState(() => _busy = false);
    }
  }

  void _typed() {
    final v = double.tryParse(_price.text.replaceAll(RegExp(r'[^0-9.]'), ''));
    if (v == null || v <= 0) return;
    _price.clear();
    FocusManager.instance.primaryFocus?.unfocus();
    _move(ask: v, mine: '${money(v)}, can?');
  }

  Face get _face => switch (_s?['event']) {
    'annoyed' || 'impatient' => Face.annoyed,
    'walk' => Face.sad,
    'accept' || 'thanks' || 'happy' => Face.happy,
    _ => Face.neutral,
  };

  @override
  Widget build(BuildContext context) {
    final s = _s;
    final product = s?['product'] as Map?;
    final customer = s?['customer'] as Map?;
    return Scaffold(
      appBar: AppBar(
        title: const Text('🧺 Your own stall'),
        backgroundColor: Palette.cream,
        actions: [
          if (s?['totals'] case final Map t)
            Padding(
              padding: const EdgeInsets.only(right: 14),
              child: Center(
                child: Text(
                  '${t['sales']} sold · ${money(t['profit'] as num)} profit',
                  style: const TextStyle(color: Palette.soft, fontWeight: FontWeight.w600),
                ),
              ),
            ),
        ],
      ),
      backgroundColor: Palette.cream,
      body: TileBackground(
        child: Column(
          children: [
            // the customer in front of your counter
            Container(
              height: 228,
              width: double.infinity,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  // ✨ the golden stall from the shop
                  colors: s?['golden'] == true
                      ? const [Color(0xFFFFE08A), Color(0xFFFFF6D5)]
                      : const [Color(0xFFDDF1EC), Color(0xFFFFF6E5)],
                ),
              ),
              child: Stack(
                children: [
                  Positioned.fill(child: StallDecor(owned: {for (final d in (s?['decor'] as List? ?? const [])) '$d'})),
                  Positioned.fill(
                    child: customer == null
                        ? Center(
                            child: _closed == null
                                ? const CircularProgressIndicator()
                                : Padding(
                                    key: const ValueKey('shop_closed'),
                                    padding: const EdgeInsets.all(24),
                                    child: Text(
                                      _closed!,
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                        color: Palette.ink,
                                        height: 1.4,
                                      ),
                                    ),
                                  ),
                          )
                        : Column(
                            children: [
                              const SizedBox(height: 6),
                              Stallholder(
                                look: Map<String, dynamic>.from(customer['look'] as Map),
                                face: _face,
                                reactKey: _react,
                                size: 104,
                              ),
                              Text(
                                '${customer['name']} wants your ${product!['emoji']} ${product['name']}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontWeight: FontWeight.w700, color: Palette.ink),
                              ),
                              // what you can tell about them, and 😍 when it's the kind of thing they love
                              Text(
                                [
                                  if ('${customer['clue'] ?? ''}'.isNotEmpty) '${customer['clue']}',
                                  if (s?['loves'] == true) '😍 loves it!',
                                ].join('  ·  '),
                                key: const ValueKey('customer_clue'),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(color: Palette.ink, fontSize: 12, fontStyle: FontStyle.italic),
                              ),
                              Text(
                                product['from'] != null
                                    ? 'You bought it at ${product['from']}\'s for ${money(product['cost'] as num)} · usually ${money(product['fair'] as num)}'
                                    : 'Wholesale, you paid ${money(product['cost'] as num)} · usually sells for ${money(product['fair'] as num)}',
                                textAlign: TextAlign.center,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(color: Palette.soft, fontSize: 13),
                              ),
                              GestureDetector(
                                onTap: () => Navigator.of(context)
                                    .push(MaterialPageRoute<void>(builder: (_) => InventoryScreen(api: widget.api))),
                                child: Text(
                                  (s!['stock'] as num) > 0
                                      ? '📦 ${s['stock']} thing${s['stock'] == 1 ? '' : 's'} in stock · see them ›'
                                      : '📦 Buy things at the market to sell them here',
                                  key: const ValueKey('shop_stock'),
                                  style: const TextStyle(
                                    color: Palette.soft,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                  ),
                  // 👋 "Not today": send this customer away (a few a day)
                  if (customer != null && s?['done'] != true && ((s?['passes_left'] ?? 0) as num) > 0)
                    Positioned(
                      top: 6,
                      right: 8,
                      child: Bouncy(
                        key: const ValueKey('shop_pass'),
                        enabled: !_busy,
                        onTap: _pass,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.9),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Text(
                            '👋 Not today (${s?['passes_left']})',
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Palette.ink),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            if (s != null && s['first_sale'] == true && s['done'] != true) _firstSaleTip(s),
            Expanded(
              child: ListView(
                controller: _scroll,
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
                children: [
                  for (final m in _msgs) Bubble(text: m.text, mine: m.mine, sparkle: m.sparkle),
                  if (_busy) const Typing(),
                  if (s != null && s['done'] == true) _result(s),
                ],
              ),
            ),
            if (s != null && s['done'] != true) _controls(s),
          ],
        ),
      ),
    );
  }

  Widget _controls(Map<String, dynamic> s) {
    final offer = (s['offer'] as num).toDouble();
    final asks = (s['suggestions'] as List).cast<num>();
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
        color: Colors.white,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                for (final a in asks)
                  Bouncy(
                    key: ValueKey('ask_$a'),
                    enabled: !_busy,
                    onTap: () => _move(ask: a.toDouble(), mine: '${money(a)}, can?'),
                    child: Pill(text: 'Ask ${money(a)}', icon: '🏷️'),
                  ),
                Bouncy(
                  key: const ValueKey('shop_take'),
                  enabled: !_busy,
                  onTap: () => _move(take: true, mine: 'Okay, ${money(offer)}. Deal!'),
                  child: Pill(text: 'Sell for ${money(offer)}', icon: '🤝', color: Palette.gold),
                ),
                Bouncy(
                  key: const ValueKey('shop_chat'),
                  enabled: !_busy,
                  onTap: () => _move(chat: true, mine: 'You have good taste! 😊'),
                  child: const Pill(text: 'Be friendly', icon: '😊'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    key: const ValueKey('shop_price'),
                    controller: _price,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    onSubmitted: (_) => _typed(),
                    decoration: InputDecoration(
                      hintText: 'Or type your price',
                      prefixText: '\$ ',
                      isDense: true,
                      filled: true,
                      fillColor: Palette.cream,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                TextButton(key: const ValueKey('shop_ask'), onPressed: _busy ? null : _typed, child: const Text('Ask')),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// 👩 Mum's tip for your very first sale (until it's over).
  Widget _firstSaleTip(Map<String, dynamic> s) {
    final product = s['product'] as Map;
    final paid = money(product['cost'] as num);
    final usual = money(product['fair'] as num);
    final tip = switch ('${s['event']}') {
      'raise' || 'accept' || 'thanks' =>
        "They came up! Ask the same price again to hold firm (if it's not too much for them, they give in), or "
            "take their offer if it's more than it cost you ($paid).",
      'annoyed' => "Too high for them! Come down a little: anything above $paid is still profit.",
      _ =>
        'Your first customer! They will offer low. Ask for the usual price ($usual) or a bit more (😍 means they '
            "love it: ask more!). It cost you $paid, so anything above that is profit.",
    };
    return Container(
      key: const ValueKey('first_sale_tip'),
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: const Color(0xFFFFF2C7), borderRadius: BorderRadius.circular(14)),
      child: Text('👩 Mum: $tip', style: const TextStyle(color: Palette.ink, height: 1.35)),
    );
  }

  Widget _result(Map<String, dynamic> s) {
    final sold = s['result'] == 'sold';
    final stars = (s['stars'] as num).toInt();
    return Container(
      key: const ValueKey('shop_result'),
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
      child: Column(
        children: [
          if (sold && moneyIn(s['notes'] as List? ?? const []) > 0) ...[
            MoneyPop(amount: moneyIn(s['notes'] as List? ?? const [])),
            const SizedBox(height: 8),
          ],
          Text(
            sold ? 'Sold for ${money(s['price'] as num)}!' : '${(s['customer'] as Map)['name']} walked away',
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: Palette.ink),
          ),
          if (sold) ...[
            Text(
              (s['profit'] as num) >= 0
                  ? 'Profit: ${money(s['profit'] as num)}'
                  : 'A loss of ${money(-(s['profit'] as num))}',
              style: const TextStyle(color: Palette.ink),
            ),
            Text(List.generate(3, (i) => i < stars ? '⭐' : '☆').join(' '), style: const TextStyle(fontSize: 22)),
          ] else
            const Text('Ask a little less next time, or be friendly first.', style: TextStyle(color: Palette.soft)),
          for (final n in (s['notes'] as List? ?? const []).cast<String>())
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                n,
                style: const TextStyle(fontWeight: FontWeight.w700, color: Palette.teal),
              ),
            ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: Bouncy(
                  onTap: () => Navigator.of(context).pop(),
                  child: const Pill(text: 'Back to market', icon: '🏮'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Bouncy(
                  key: const ValueKey('shop_next'),
                  onTap: _next,
                  child: const Pill(text: 'Next customer', icon: '🧺', color: Palette.gold),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
