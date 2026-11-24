/// Small helpers that behave exactly like the Python reference (server/hh), so the port gives the same answers.
/// Checked against app/test/fixtures/reference.json.
library;

import 'dart:math' as math;

/// Python's round() to an integer: halves go to the even neighbour (13.25/0.5 = 26.5 -> 26, not 27).
double roundHalfEven(double x) {
  final f = x.floorToDouble();
  final diff = x - f;
  if (diff > 0.5) return f + 1;
  if (diff < 0.5) return f;
  return f % 2 == 0 ? f : f + 1;
}

/// Python's round(x, nd).
double pyRound(double x, [int nd = 0]) {
  if (nd == 0) return roundHalfEven(x);
  // Decide on the exact decimal value of the double (like Python), then round half to even.
  final s = x.abs().toStringAsFixed(20);
  final dot = s.indexOf('.');
  final keep = s.substring(0, dot + 1 + nd);
  final rest = s.substring(dot + 1 + nd);
  var digits = BigInt.parse(keep.replaceAll('.', ''));
  final first = rest.codeUnitAt(0) - 48;
  final tail = rest.substring(1).replaceAll('0', '');
  final up = first > 5 || (first == 5 && (tail.isNotEmpty || digits.isOdd));
  if (up) digits += BigInt.one;
  final v = digits.toDouble() / math.pow(10, nd);
  return x < 0 ? -v : v;
}

/// Python's f"{v:.2f}".
String fixed2(double v) {
  final r = pyRound(v, 2);
  return r.toStringAsFixed(2);
}

/// Python str.capitalize().
String capitalize(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1).toLowerCase();

/// Python's first n characters (code points, so an emoji is never cut in half).
String pySlice(String s, int n) {
  final r = s.runes;
  return r.length <= n ? s : String.fromCharCodes(r.take(n));
}

/// Python str.splitlines()[0] (or '' when empty).
String firstLine(String s) {
  final parts = s.split(RegExp('\r\n|[\n\r\u000b\u000c\u001c-\u001e\u0085  ]'));
  return parts.isEmpty ? '' : parts.first;
}

/// Python str.split() with no arguments.
List<String> pySplit(String s) => s.trim().isEmpty ? [] : s.trim().split(RegExp(r'\s+'));

/// Python str.strip(chars).
String stripChars(String s, String chars) {
  var a = 0, b = s.length;
  while (a < b && chars.contains(s[a])) {
    a++;
  }
  while (b > a && chars.contains(s[b - 1])) {
    b--;
  }
  return s.substring(a, b);
}

/// Fullwidth digits (１５) count as digits in Python's regexes; make them plain so Dart matches the same.
String plainDigits(String s) =>
    s.replaceAllMapped(RegExp('[０-９]'), (m) => String.fromCharCode(m[0]!.codeUnitAt(0) - 0xFF10 + 48));

/// A regex written in Python syntax, with Python's Unicode meaning of \w, \W and \b (Dart's are ASCII only).
RegExp pyRe(String pattern, {bool ignoreCase = false}) {
  const w = r'[\p{L}\p{N}_]';
  const nw = r'[^\p{L}\p{N}_]';
  final b = '(?:(?<=$w)(?!$w)|(?<!$w)(?=$w))';
  final out = StringBuffer();
  var inClass = false;
  for (var i = 0; i < pattern.length; i++) {
    final c = pattern[i];
    if (c == r'\' && i + 1 < pattern.length) {
      final n = pattern[i + 1];
      i++;
      if (n == 'w') {
        out.write(inClass ? r'\p{L}\p{N}_' : w);
      } else if (n == 'W') {
        out.write(inClass ? r'\P{L}' : nw); // only used outside classes in our patterns
      } else if (n == 'b' && !inClass) {
        out.write(b);
      } else {
        out.write('\\$n');
      }
      continue;
    }
    if (c == '[' && !inClass) inClass = true;
    if (c == ']' && inClass) inClass = false;
    out.write(c);
  }
  return RegExp(out.toString(), unicode: true, caseSensitive: !ignoreCase);
}
