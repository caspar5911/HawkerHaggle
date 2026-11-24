import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'sfx.dart';

class Palette {
  static const cream = Color(0xFFFFF6E5);
  static const tile = Color(0xFFFDEBCB);
  static const grout = Color(0xFFF3D9AE);
  static const ink = Color(0xFF3B2A2A);
  static const soft = Color(0xFF8A6F63);
  static const red = Color(0xFFE85D5D);
  static const teal = Color(0xFF3FB39B);
  static const gold = Color(0xFFFFC94A);
  static const green = Color(0xFF6CC56C);
  static const sky = Color(0xFF8FD3FF);
  static const awnings = [
    [Color(0xFFE85D5D), Colors.white],
    [Color(0xFF3FB39B), Colors.white],
    [Color(0xFFFFB347), Colors.white],
    [Color(0xFF8E7CC3), Colors.white],
  ];
}

String money(num v) => v == v.roundToDouble() ? '\$${v.toInt()}' : '\$${v.toStringAsFixed(2)}';

/// Soft kopitiam floor tiles behind everything.
class TileBackground extends StatelessWidget {
  const TileBackground({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => CustomPaint(painter: _Tiles(), child: child);
}

class _Tiles extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = Palette.cream);
    const s = 46.0;
    final tile = Paint()..color = Palette.tile;
    final dot = Paint()..color = Palette.grout;
    for (var y = 0.0; y < size.height + s; y += s) {
      for (var x = ((y / s).floor().isEven ? 0.0 : s / 2) - s; x < size.width + s; x += s) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(Rect.fromLTWH(x + 3, y + 3, s - 6, s - 6), const Radius.circular(8)),
          tile,
        );
        canvas.drawCircle(Offset(x + s / 2, y + s / 2), 3, dot);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// A scalloped, striped stall awning.
class Awning extends StatelessWidget {
  const Awning({super.key, required this.colors, this.height = 46});
  final List<Color> colors;
  final double height;
  @override
  Widget build(BuildContext context) => SizedBox(
    height: height,
    width: double.infinity,
    child: CustomPaint(painter: _AwningPainter(colors)),
  );
}

class _AwningPainter extends CustomPainter {
  _AwningPainter(this.colors);
  final List<Color> colors;
  @override
  void paint(Canvas canvas, Size size) {
    const n = 8;
    final sw = size.width / n;
    final body = size.height * 0.68;
    for (var i = 0; i < n; i++) {
      final p = Paint()..color = colors[i % 2];
      canvas.drawRect(Rect.fromLTWH(i * sw, 0, sw + 0.5, body), p);
      canvas.drawArc(Rect.fromLTWH(i * sw, body - sw / 2, sw, sw), 0, math.pi, true, p);
    }
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, 5), Paint()..color = Colors.black.withValues(alpha: 0.08));
  }

  @override
  bool shouldRepaint(_AwningPainter old) => old.colors != colors;
}

/// A button that squishes when pressed and gives a small buzz.
class Bouncy extends StatefulWidget {
  const Bouncy({super.key, required this.child, required this.onTap, this.onLongPress, this.enabled = true});
  final Widget child;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final bool enabled;
  @override
  State<Bouncy> createState() => _BouncyState();
}

class _BouncyState extends State<Bouncy> {
  bool _down = false;
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: widget.enabled ? (_) => setState(() => _down = true) : null,
      onTapCancel: () => setState(() => _down = false),
      onLongPress: widget.enabled && widget.onLongPress != null
          ? () {
              setState(() => _down = false);
              HapticFeedback.mediumImpact();
              widget.onLongPress!();
            }
          : null,
      onTapUp: widget.enabled
          ? (_) {
              setState(() => _down = false);
              HapticFeedback.lightImpact();
              Sfx.play('pop', volume: 0.5);
              widget.onTap();
            }
          : null,
      child: AnimatedScale(
        scale: _down ? 0.92 : 1,
        duration: const Duration(milliseconds: 110),
        curve: Curves.easeOutBack,
        child: AnimatedOpacity(
          opacity: widget.enabled ? 1 : 0.45,
          duration: const Duration(milliseconds: 200),
          child: widget.child,
        ),
      ),
    );
  }
}

/// A chunky rounded pill used for moves and buttons.
class Pill extends StatelessWidget {
  const Pill({super.key, required this.text, this.color = Colors.white, this.textColor = Palette.ink, this.icon});
  final String text;
  final Color color;
  final Color textColor;
  final String? icon;
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.10), offset: const Offset(0, 4), blurRadius: 0)],
        border: Border.all(color: Colors.black.withValues(alpha: 0.06), width: 2),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Text(icon!, style: const TextStyle(fontSize: 18)),
            ),
          Flexible(
            child: Text(
              text,
              style: TextStyle(color: textColor, fontWeight: FontWeight.w600, fontSize: 15),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }
}

/// The price tag: flips to the new price with a little bounce, the opening price crossed out above it.
class PriceTag extends StatelessWidget {
  const PriceTag({super.key, required this.ask, required this.opening, this.deal});
  final num ask;
  final num opening;
  final num? deal;
  @override
  Widget build(BuildContext context) {
    final shown = deal ?? ask;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 10),
      decoration: BoxDecoration(
        color: deal != null ? Palette.green : Palette.gold,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.12), offset: const Offset(0, 4))],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (shown < opening)
            Text(
              money(opening),
              style: TextStyle(
                fontSize: 13,
                color: Palette.ink.withValues(alpha: 0.55),
                decoration: TextDecoration.lineThrough,
              ),
            ),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 450),
            transitionBuilder: (child, a) => ScaleTransition(
              scale: CurvedAnimation(parent: a, curve: Curves.elasticOut),
              child: FadeTransition(opacity: a, child: child),
            ),
            child: Text(
              money(shown),
              key: ValueKey(shown),
              style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w700, color: Palette.ink),
            ),
          ),
        ],
      ),
    );
  }
}

/// Patience: drains smoothly, shakes when it drops a lot, goes from green to red.
class PatienceBar extends StatefulWidget {
  const PatienceBar({super.key, required this.value});
  final int value;
  @override
  State<PatienceBar> createState() => _PatienceBarState();
}

class _PatienceBarState extends State<PatienceBar> with SingleTickerProviderStateMixin {
  late final AnimationController _shake = AnimationController(vsync: this, duration: const Duration(milliseconds: 500));

  @override
  void didUpdateWidget(PatienceBar old) {
    super.didUpdateWidget(old);
    if (old.value - widget.value >= 10) {
      _shake.forward(from: 0);
      HapticFeedback.mediumImpact();
    }
  }

  @override
  void dispose() {
    _shake.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final v = widget.value.clamp(0, 100) / 100;
    final color = Color.lerp(Palette.red, Palette.green, v)!;
    return AnimatedBuilder(
      animation: _shake,
      builder: (context, child) => Transform.translate(
        offset: Offset(math.sin(_shake.value * math.pi * 6) * 5 * (1 - _shake.value), 0),
        child: child,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            v > 0.6 ? '😊 Patience' : (v > 0.3 ? '😐 Patience' : '😤 Patience'),
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Palette.soft),
          ),
          const SizedBox(height: 4),
          Container(
            width: 120,
            height: 14,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.black.withValues(alpha: 0.08), width: 2),
            ),
            child: Align(
              alignment: Alignment.centerLeft,
              child: TweenAnimationBuilder<double>(
                tween: Tween(end: v),
                duration: const Duration(milliseconds: 600),
                curve: Curves.easeOutCubic,
                builder: (_, x, _) => FractionallySizedBox(
                  widthFactor: x.clamp(0.0, 1.0),
                  child: Container(
                    decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(6)),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A speech bubble that pops in.
class Bubble extends StatelessWidget {
  const Bubble({super.key, required this.text, required this.mine, this.sparkle = false});
  final String text;
  final bool mine;
  final bool sparkle;
  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeOutBack,
      builder: (context, t, child) => Opacity(
        opacity: t.clamp(0.0, 1.0),
        child: Transform.scale(
          scale: 0.6 + 0.4 * t,
          alignment: mine ? Alignment.bottomRight : Alignment.bottomLeft,
          child: child,
        ),
      ),
      child: Align(
        alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 290),
          margin: const EdgeInsets.symmetric(vertical: 5),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: mine ? Palette.teal : Colors.white,
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(18),
              topRight: const Radius.circular(18),
              bottomLeft: Radius.circular(mine ? 18 : 4),
              bottomRight: Radius.circular(mine ? 4 : 18),
            ),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.08), offset: const Offset(0, 3))],
          ),
          child: Text(
            (sparkle ? '✨ ' : '') + text,
            style: TextStyle(fontSize: 15, color: mine ? Colors.white : Palette.ink, height: 1.3),
          ),
        ),
      ),
    );
  }
}

/// "..." while the stallholder thinks.
class Typing extends StatefulWidget {
  const Typing({super.key});
  @override
  State<Typing> createState() => _TypingState();
}

class _TypingState extends State<Typing> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))
    ..repeat();
  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 5),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18)),
        child: AnimatedBuilder(
          animation: _c,
          builder: (_, _) => Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < 3; i++)
                Transform.translate(
                  offset: Offset(0, -4 * math.max(0, math.sin((_c.value - i * 0.15) * 2 * math.pi))),
                  child: Container(
                    width: 8,
                    height: 8,
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    decoration: const BoxDecoration(color: Palette.soft, shape: BoxShape.circle),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Stars that pop in one after another.
class Stars extends StatelessWidget {
  const Stars({super.key, required this.count, this.size = 44, this.animate = true});
  final int count;
  final double size;
  final bool animate;
  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < 3; i++)
          TweenAnimationBuilder<double>(
            tween: Tween(begin: animate ? 0 : 1, end: 1),
            duration: Duration(milliseconds: 500 + i * 260),
            curve: Interval(i * 0.3, 1, curve: Curves.elasticOut),
            builder: (_, t, _) => Transform.scale(
              scale: t,
              child: Text(
                i < count ? '⭐' : '☆',
                style: TextStyle(fontSize: size, color: i < count ? null : Palette.soft.withValues(alpha: 0.4)),
              ),
            ),
          ),
      ],
    );
  }
}

/// Confetti and coins bursting out, then falling.
class Confetti extends StatefulWidget {
  const Confetti({super.key});
  @override
  State<Confetti> createState() => _ConfettiState();
}

class _ConfettiState extends State<Confetti> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 2600))
    ..forward();
  final _bits = List.generate(70, (i) {
    final r = math.Random(i * 7919);
    return (
      angle: -math.pi / 2 + (r.nextDouble() - 0.5) * 2.2,
      speed: 420 + r.nextDouble() * 520,
      spin: (r.nextDouble() - 0.5) * 12,
      color: [Palette.red, Palette.gold, Palette.teal, Palette.sky, const Color(0xFFFF8FA3)][r.nextInt(5)],
      coin: r.nextDouble() < 0.25,
      size: 7 + r.nextDouble() * 7,
    );
  });

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _c,
        builder: (_, _) => CustomPaint(size: Size.infinite, painter: _ConfettiPainter(_bits, _c.value)),
      ),
    );
  }
}

class _ConfettiPainter extends CustomPainter {
  _ConfettiPainter(this.bits, this.t);
  final List bits;
  final double t;
  @override
  void paint(Canvas canvas, Size size) {
    final origin = Offset(size.width / 2, size.height * 0.45);
    final s = t * 2.6;
    for (final b in bits) {
      final v = Offset(math.cos(b.angle), math.sin(b.angle)) * (b.speed as double);
      final pos = origin + v * s * 0.55 + Offset(0, 900 * s * s * 0.5 * 0.55);
      final fade = (1 - t).clamp(0.0, 1.0);
      canvas.save();
      canvas.translate(pos.dx, pos.dy);
      canvas.rotate(b.spin * s);
      if (b.coin as bool) {
        canvas.drawCircle(Offset.zero, b.size, Paint()..color = Palette.gold.withValues(alpha: fade));
        canvas.drawCircle(Offset.zero, b.size * 0.6, Paint()..color = const Color(0xFFFFE08A).withValues(alpha: fade));
      } else {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(center: Offset.zero, width: b.size, height: b.size * 0.55),
            const Radius.circular(2),
          ),
          Paint()..color = (b.color as Color).withValues(alpha: fade),
        );
      }
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_ConfettiPainter old) => old.t != t;
}
