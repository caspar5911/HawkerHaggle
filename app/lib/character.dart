import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

/// How a stallholder's face looks right now.
enum Face { neutral, happy, annoyed, angry, surprised, sad }

/// The face for a game event from the server.
Face faceFor(String event, double mood) {
  switch (event) {
    case 'accept':
    case 'flattered':
    case 'regular':
    case 'bulk':
    case 'competitor_drop':
    case 'plead':
    case 'confirm':
      return Face.happy;
    case 'callback':
    case 'confused':
    case 'clarify':
      return Face.surprised;
    case 'final':
    case 'competitor_annoyed':
    case 'flattery_tired':
    case 'plead_no':
    case 'pity_tired':
      return Face.annoyed;
    case 'insulted':
    case 'rude':
      return Face.angry;
    case 'letgo':
    case 'refuse':
    case 'pity':
    case 'budget_best':
      return Face.sad;
    default:
      return mood >= 1.5 ? Face.happy : (mood <= -1 ? Face.annoyed : Face.neutral);
  }
}

Color hex(String s) => Color(int.parse(s.replaceFirst('#', ''), radix: 16) | 0xFF000000);

/// A chibi stallholder that breathes, blinks, talks and reacts. [reactKey] changes on every new line: the
/// character talks and, depending on [face], jumps, shakes or squishes.
class Stallholder extends StatefulWidget {
  const Stallholder({super.key, required this.look, this.face = Face.neutral, this.reactKey = 0, this.size = 200});

  final Map<String, dynamic> look;
  final Face face;
  final int reactKey;
  final double size;

  @override
  State<Stallholder> createState() => _StallholderState();
}

class _StallholderState extends State<Stallholder> with TickerProviderStateMixin {
  late final AnimationController _idle = AnimationController(vsync: this, duration: const Duration(milliseconds: 2600))
    ..repeat();
  late final AnimationController _blink = AnimationController(vsync: this, duration: const Duration(milliseconds: 140));
  late final AnimationController _react = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));
  Timer? _blinkTimer;
  final _rng = math.Random();

  @override
  void initState() {
    super.initState();
    _scheduleBlink();
    _react.forward();
  }

  void _scheduleBlink() {
    _blinkTimer = Timer(Duration(milliseconds: 1800 + _rng.nextInt(3200)), () async {
      if (!mounted) return;
      await _blink.forward();
      if (!mounted) return;
      await _blink.reverse();
      _scheduleBlink();
    });
  }

  @override
  void didUpdateWidget(Stallholder old) {
    super.didUpdateWidget(old);
    if (old.reactKey != widget.reactKey) _react.forward(from: 0);
  }

  @override
  void dispose() {
    _blinkTimer?.cancel();
    _idle.dispose();
    _blink.dispose();
    _react.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([_idle, _blink, _react]),
      builder: (context, _) {
        final t = _idle.value * 2 * math.pi;
        final r = Curves.easeOut.transform(_react.value);
        final live = _react.isAnimating ? 1 - r : 0.0;
        double dx = 0, dy = math.sin(t) * 3, scale = 1;
        switch (widget.face) {
          case Face.happy:
          case Face.surprised:
            dy -= math.sin(math.pi * math.min(1, _react.value * 1.6)) * 22 * (_react.isAnimating ? 1 : 0);
            break;
          case Face.angry:
          case Face.annoyed:
            dx = math.sin(_react.value * math.pi * 8) * 7 * live;
            break;
          case Face.sad:
            dy += 6 * live;
            break;
          case Face.neutral:
            scale = 1 + 0.04 * math.sin(math.pi * _react.value) * (_react.isAnimating ? 1 : 0);
        }
        // mouth flaps while the new line is being "said"
        final talking = _react.isAnimating && _react.value < 0.7 && (math.sin(_react.value * 40) > 0);
        return Transform.translate(
          offset: Offset(dx, dy),
          child: Transform.scale(
            scale: scale,
            alignment: Alignment.bottomCenter,
            child: SizedBox(
              width: widget.size,
              height: widget.size * 1.18,
              child: CustomPaint(
                painter: _ChibiPainter(
                  look: widget.look,
                  face: widget.face,
                  blink: _blink.value,
                  breathe: math.sin(t),
                  talking: talking,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _ChibiPainter extends CustomPainter {
  _ChibiPainter({
    required this.look,
    required this.face,
    required this.blink,
    required this.breathe,
    required this.talking,
  });

  final Map<String, dynamic> look;
  final Face face;
  final double blink;
  final double breathe;
  final bool talking;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final skin = hex(look['skin'] ?? '#F5D0B5');
    final hair = hex(look['hair'] ?? '#3A3030');
    final shirt = hex(look['shirt'] ?? '#F28FA3');
    final apron = hex(look['apron'] ?? '#FFF2C7');
    final acc = (look['accessory'] ?? '') as String;
    final ink = const Color(0xFF3B2A2A);
    final p = Paint()..isAntiAlias = true;

    // ground shadow
    p.color = Colors.black.withValues(alpha: 0.10);
    canvas.drawOval(Rect.fromCenter(center: Offset(w / 2, h * 0.985), width: w * 0.62, height: h * 0.05), p);

    // body (breathes a little)
    final bodyTop = h * 0.60 - breathe * 1.2;
    final body = RRect.fromRectAndCorners(
      Rect.fromLTRB(w * 0.2, bodyTop, w * 0.8, h * 0.98),
      topLeft: Radius.circular(w * 0.22),
      topRight: Radius.circular(w * 0.22),
      bottomLeft: Radius.circular(w * 0.08),
      bottomRight: Radius.circular(w * 0.08),
    );
    p.color = shirt;
    canvas.drawRRect(body, p);
    // arms + hands
    for (final side in [-1, 1]) {
      final ax = w / 2 + side * w * 0.31;
      p.color = shirt;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: Offset(ax, bodyTop + h * 0.13), width: w * 0.13, height: h * 0.2),
          Radius.circular(w * 0.07),
        ),
        p,
      );
      p.color = skin;
      canvas.drawCircle(Offset(ax, bodyTop + h * 0.23), w * 0.06, p);
    }
    // apron with a pocket
    p.color = apron;
    final apronRect = RRect.fromRectAndRadius(
      Rect.fromLTRB(w * 0.3, bodyTop + h * 0.07, w * 0.7, h * 0.96),
      Radius.circular(w * 0.06),
    );
    canvas.drawRRect(apronRect, p);
    p.color = Colors.black.withValues(alpha: 0.06);
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTRB(w * 0.4, h * 0.8, w * 0.6, h * 0.89), Radius.circular(w * 0.03)),
      p,
    );

    // towel round the neck (fishmonger)
    if (acc == 'towel') {
      p.color = Colors.white;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTRB(w * 0.24, bodyTop - h * 0.01, w * 0.76, bodyTop + h * 0.06),
          Radius.circular(w * 0.05),
        ),
        p,
      );
      p.color = const Color(0xFF7FB7D9);
      canvas.drawRect(Rect.fromLTRB(w * 0.24, bodyTop + h * 0.02, w * 0.76, bodyTop + h * 0.03), p);
    }

    // head
    final c = Offset(w / 2, h * 0.36 + breathe * 0.6);
    final r = w * 0.31;
    if (acc == 'tudung') {
      // headscarf: drapes to the shoulders, face shows through an oval
      p.color = shirt.withValues(alpha: 1);
      final scarf = Path()
        ..addOval(Rect.fromCircle(center: c, radius: r * 1.12))
        ..addRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTRB(c.dx - r * 1.05, c.dy, c.dx + r * 1.05, bodyTop + h * 0.08),
            Radius.circular(r * 0.5),
          ),
        );
      canvas.drawPath(scarf, p);
      p.color = Color.lerp(shirt, Colors.white, 0.25)!;
      canvas.drawCircle(Offset(c.dx + r * 0.75, c.dy - r * 0.55), r * 0.12, p);
      p.color = skin;
      canvas.drawOval(Rect.fromCenter(center: c.translate(0, r * 0.12), width: r * 1.62, height: r * 1.7), p);
    } else {
      // hair behind the head
      p.color = hair;
      if (acc == 'perm') {
        for (var i = 0; i < 11; i++) {
          final a = math.pi + i * math.pi / 10;
          canvas.drawCircle(c + Offset(math.cos(a), math.sin(a)) * r * 0.98, r * 0.3, p);
        }
      } else {
        canvas.drawCircle(c.translate(0, -r * 0.08), r * 1.02, p);
      }
      p.color = skin;
      canvas.drawCircle(c, r, p);
      // ears
      canvas.drawCircle(c.translate(-r * 0.98, r * 0.12), r * 0.16, p);
      canvas.drawCircle(c.translate(r * 0.98, r * 0.12), r * 0.16, p);
      // fringe / top hair
      p.color = hair;
      if (acc == 'perm') {
        for (var i = 0; i < 6; i++) {
          canvas.drawCircle(c.translate(-r * 0.62 + i * r * 0.25, -r * 0.72 + (i.isEven ? 0 : r * 0.06)), r * 0.24, p);
        }
      } else {
        canvas.drawArc(
          Rect.fromCircle(center: c.translate(0, -r * 0.05), radius: r),
          math.pi * 1.08,
          math.pi * 0.84,
          false,
          p..style = PaintingStyle.fill,
        );
      }
      if (acc == 'cap') {
        p.color = apron;
        canvas.drawArc(Rect.fromCircle(center: c.translate(0, -r * 0.18), radius: r * 1.02), math.pi, math.pi, true, p);
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTRB(c.dx - r * 0.2, c.dy - r * 0.3, c.dx + r * 1.35, c.dy - r * 0.12),
            Radius.circular(r * 0.1),
          ),
          p,
        );
        p.color = Colors.white.withValues(alpha: 0.9);
        canvas.drawCircle(c.translate(0, -r * 0.78), r * 0.1, p);
      }
    }

    // blush
    p.color = const Color(0xFFFF8FA3).withValues(alpha: face == Face.angry ? 0.75 : 0.45);
    for (final side in [-1, 1]) {
      canvas.drawOval(
        Rect.fromCenter(center: c.translate(side * r * 0.55, r * 0.32), width: r * 0.36, height: r * 0.2),
        p,
      );
    }

    _eyes(canvas, c, r, ink);
    _brows(canvas, c, r, ink);
    _mouth(canvas, c, r, ink);
    _extras(canvas, c, r);
  }

  void _eyes(Canvas canvas, Offset c, double r, Color ink) {
    final p = Paint()
      ..color = ink
      ..isAntiAlias = true;
    final line = Paint()
      ..color = ink
      ..style = PaintingStyle.stroke
      ..strokeWidth = r * 0.07
      ..strokeCap = StrokeCap.round;
    for (final side in [-1, 1]) {
      final e = c.translate(side * r * 0.36, r * 0.02);
      if (face == Face.happy) {
        canvas.drawArc(
          Rect.fromCenter(center: e.translate(0, r * 0.06), width: r * 0.3, height: r * 0.28),
          math.pi * 1.1,
          math.pi * 0.8,
          false,
          line,
        );
        continue;
      }
      final openness = (1 - blink) * (face == Face.annoyed ? 0.55 : (face == Face.surprised ? 1.25 : 1.0));
      if (openness < 0.12) {
        canvas.drawLine(e.translate(-r * 0.12, 0), e.translate(r * 0.12, 0), line);
        continue;
      }
      final eh = r * 0.3 * openness, ew = r * (face == Face.surprised ? 0.26 : 0.22);
      canvas.drawOval(Rect.fromCenter(center: e, width: ew, height: eh), p);
      if (face == Face.annoyed) {
        canvas.drawLine(e.translate(-ew * 0.7, -eh * 0.35), e.translate(ew * 0.7, -eh * 0.35), line);
      }
      final shine = Paint()..color = Colors.white;
      canvas.drawCircle(e.translate(-ew * 0.18, -eh * 0.2), ew * 0.2, shine);
    }
  }

  void _brows(Canvas canvas, Offset c, double r, Color ink) {
    if (face == Face.neutral || face == Face.happy) return;
    final line = Paint()
      ..color = ink
      ..style = PaintingStyle.stroke
      ..strokeWidth = r * 0.06
      ..strokeCap = StrokeCap.round;
    for (final side in [-1, 1]) {
      final b = c.translate(side * r * 0.36, -r * 0.27);
      final tilt = switch (face) {
        Face.angry => 0.12,
        Face.annoyed => 0.05,
        Face.sad => -0.1,
        _ => -0.04,
      };
      final lift = face == Face.surprised ? -r * 0.08 : 0.0;
      canvas.drawLine(
        b.translate(-side * r * 0.13, -tilt * r + lift),
        b.translate(side * r * 0.13, tilt * r + lift),
        line,
      );
    }
  }

  void _mouth(Canvas canvas, Offset c, double r, Color ink) {
    final m = c.translate(0, r * 0.45);
    final fill = Paint()..color = const Color(0xFF7A2E3A);
    final line = Paint()
      ..color = ink
      ..style = PaintingStyle.stroke
      ..strokeWidth = r * 0.06
      ..strokeCap = StrokeCap.round;
    if (talking || face == Face.surprised) {
      canvas.drawOval(Rect.fromCenter(center: m, width: r * 0.22, height: r * (talking ? 0.2 : 0.26)), fill);
      return;
    }
    switch (face) {
      case Face.happy:
        final path = Path()
          ..moveTo(m.dx - r * 0.22, m.dy - r * 0.05)
          ..quadraticBezierTo(m.dx, m.dy + r * 0.32, m.dx + r * 0.22, m.dy - r * 0.05)
          ..close();
        canvas.drawPath(path, fill);
        canvas.drawCircle(m.translate(0, r * 0.1), r * 0.07, Paint()..color = const Color(0xFFFF8FA3));
        break;
      case Face.angry:
      case Face.sad:
        canvas.drawArc(
          Rect.fromCenter(center: m.translate(0, r * 0.1), width: r * 0.36, height: r * 0.22),
          math.pi * 1.15,
          math.pi * 0.7,
          false,
          line,
        );
        break;
      case Face.annoyed:
        canvas.drawLine(m.translate(-r * 0.14, 0), m.translate(r * 0.14, r * 0.02), line);
        break;
      default:
        canvas.drawArc(
          Rect.fromCenter(center: m.translate(0, -r * 0.04), width: r * 0.32, height: r * 0.2),
          math.pi * 0.15,
          math.pi * 0.7,
          false,
          line,
        );
    }
  }

  void _extras(Canvas canvas, Offset c, double r) {
    if (face == Face.angry) {
      final vein = Paint()
        ..color = const Color(0xFFE5484D)
        ..style = PaintingStyle.stroke
        ..strokeWidth = r * 0.07
        ..strokeCap = StrokeCap.round;
      final v = c.translate(r * 0.72, -r * 0.72);
      for (final a in [0.0, math.pi / 2, math.pi, math.pi * 1.5]) {
        final d = Offset(math.cos(a), math.sin(a));
        canvas.drawLine(v + d * r * 0.05, v + d * r * 0.17, vein);
      }
    }
    if (face == Face.sad || face == Face.annoyed) {
      final drop = Path()
        ..moveTo(c.dx + r * 0.82, c.dy - r * 0.38)
        ..quadraticBezierTo(c.dx + r * 0.94, c.dy - r * 0.15, c.dx + r * 0.82, c.dy - r * 0.08)
        ..quadraticBezierTo(c.dx + r * 0.7, c.dy - r * 0.15, c.dx + r * 0.82, c.dy - r * 0.38);
      canvas.drawPath(drop, Paint()..color = const Color(0xFF8FD3FF));
    }
  }

  @override
  bool shouldRepaint(_ChibiPainter old) =>
      old.blink != blink || old.face != face || old.breathe != breathe || old.talking != talking || old.look != look;
}
