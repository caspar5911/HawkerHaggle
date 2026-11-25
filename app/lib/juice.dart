// "Juice": small effects that make every move feel physical. A price tag that rolls down with a ka-ching and a burst
// of coins, a jolt when the stallholder is insulted, a DEAL! stamp. All short and finite; "Reduce motion" (Settings,
// or the phone's own setting) turns the movement off.
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class Motion {
  Motion._();
  static bool reduced = false;
  static const _storage = FlutterSecureStorage();

  static Future<void> init() async {
    try {
      reduced = (await _storage.read(key: 'reduce_motion')) == '1';
    } catch (_) {}
  }

  static Future<void> set(bool on) async {
    reduced = on;
    try {
      await _storage.write(key: 'reduce_motion', value: on ? '1' : '0');
    } catch (_) {}
  }

  /// Less movement: the player's choice, or the phone's accessibility setting.
  static bool less(BuildContext context) => reduced || (MediaQuery.maybeDisableAnimationsOf(context) ?? false);
}

/// Shakes its child briefly each time [trigger] changes (a stallholder slamming the counter).
class Jolt extends StatefulWidget {
  const Jolt({super.key, required this.trigger, required this.child, this.strength = 9});
  final int trigger;
  final Widget child;
  final double strength;
  @override
  State<Jolt> createState() => _JoltState();
}

class _JoltState extends State<Jolt> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 320));

  @override
  void didUpdateWidget(Jolt old) {
    super.didUpdateWidget(old);
    if (old.trigger != widget.trigger && !Motion.less(context)) _c.forward(from: 0);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _c,
    child: widget.child,
    builder: (_, child) {
      final t = _c.value;
      final dx = t == 0 || t == 1 ? 0.0 : math.sin(t * math.pi * 7) * widget.strength * (1 - t);
      return Transform.translate(offset: Offset(dx, 0), child: child);
    },
  );
}

/// The price tag's number: rolls from the old price to the new one, and the tag hops; a little shower of coins when
/// the price drops.
class RollingPrice extends StatefulWidget {
  const RollingPrice({super.key, required this.value, required this.style, required this.format});
  final double value;
  final TextStyle style;
  final String Function(num) format;
  @override
  State<RollingPrice> createState() => _RollingPriceState();
}

class _RollingPriceState extends State<RollingPrice> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 650));
  late double _from = widget.value;
  bool _dropped = false;

  @override
  void didUpdateWidget(RollingPrice old) {
    super.didUpdateWidget(old);
    if (old.value != widget.value) {
      _from = old.value;
      _dropped = widget.value < old.value;
      if (Motion.less(context)) {
        _c.value = 1;
      } else {
        _c.forward(from: 0);
      }
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _c,
    builder: (_, _) {
      final t = Curves.easeOutCubic.transform(_c.isAnimating ? _c.value : 1);
      // in 50-cent steps while it rolls, the exact price at the end
      final v = t >= 1 ? widget.value : ((_from + (widget.value - _from) * t) * 2).round() / 2;
      final hop = _c.isAnimating ? math.sin(_c.value * math.pi) * -6 : 0.0;
      return Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          Transform.translate(
            offset: Offset(0, hop),
            child: Text(widget.format(v), style: widget.style),
          ),
          if (_dropped && _c.isAnimating)
            for (var i = 0; i < 5; i++)
              Positioned(
                left: 6.0 + i * 14,
                top: -6 - 46 * Curves.easeOut.transform(_c.value) * (0.6 + 0.1 * i),
                child: Opacity(
                  opacity: (1 - _c.value).clamp(0.0, 1.0),
                  child: const Text('🪙', style: TextStyle(fontSize: 14)),
                ),
              ),
        ],
      );
    },
  );
}

/// "DEAL!" stamped onto the screen when a deal closes.
class DealStamp extends StatefulWidget {
  const DealStamp({super.key, required this.text});
  final String text;
  @override
  State<DealStamp> createState() => _DealStampState();
}

class _DealStampState extends State<DealStamp> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 520))..forward();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final still = Motion.less(context);
    return IgnorePointer(
      child: Center(
        child: AnimatedBuilder(
          animation: _c,
          builder: (_, child) {
            final t = still ? 1.0 : Curves.easeOutBack.transform(_c.value);
            return Opacity(
              opacity: still ? 1 : _c.value.clamp(0.0, 1.0),
              child: Transform.rotate(
                angle: -0.18,
                child: Transform.scale(scale: still ? 1 : 2.4 - 1.4 * t, child: child),
              ),
            );
          },
          child: Container(
            key: const ValueKey('deal_stamp'),
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 10),
            decoration: BoxDecoration(
              border: Border.all(color: const Color(0xFFD94848), width: 5),
              borderRadius: BorderRadius.circular(14),
              color: Colors.white.withValues(alpha: 0.85),
            ),
            child: Text(
              widget.text,
              style: const TextStyle(
                fontSize: 40,
                fontWeight: FontWeight.w800,
                color: Color(0xFFD94848),
                letterSpacing: 2,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
