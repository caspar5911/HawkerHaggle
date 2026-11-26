/// 🔔 The daily reminder: one gentle notification a day at the time the player picks, only if they switch it on
/// (Settings). Made on the phone, nothing from a server: the next week's reminders are planned ahead and planned
/// again each time the game opens and after each haggle (so a day already played gets none). Android app only.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'core/legendary.dart';
import 'core/progress.dart' show dayKey, stableHash;

typedef Nudge = ({DateTime at, String title, String body});

/// The reminders for the next [days] days at [hour]:[minute] (Singapore time, like the market's week). Today only if
/// that time is still ahead and the player hasn't played yet. A legendary day says so.
List<Nudge> planReminders({
  required DateTime now,
  required int hour,
  required int minute,
  required bool playedToday,
  required Map<String, String> stallNames,
  int days = 7,
}) {
  final out = <Nudge>[];
  for (var d = 0; d < days; d++) {
    final day = DateTime(now.year, now.month, now.day + d);
    final at = DateTime(day.year, day.month, day.day, hour, minute);
    if (d == 0 && (playedToday || !at.isAfter(now))) continue;
    final key = dayKey(day);
    final legend = legendaryOn(key);
    if (legend != null) {
      final who = stallNames[legend.$1] ?? 'the market';
      out.add((
        at: at,
        title: '✨ Legendary today only!',
        body: '${legend.$2['emoji']} A ${legend.$2['name']} at $who\'s. Gone tomorrow!',
      ));
      continue;
    }
    final lines = _lines(stallNames);
    final (title, body) = lines[stableHash('hawker-haggle-nudge-$key') % lines.length];
    out.add((at: at, title: title, body: body));
  }
  return out;
}

List<(String, String)> _lines(Map<String, String> names) => [
  ("📝 Mum's list is ready", "Today's shopping list is waiting. Can you stay under budget?"),
  ('🥭 Fresh at the market', '${names['mei'] ?? 'Auntie Mei'} saved the sweetest fruit for you today.'),
  ('🐟 Just in this morning', '${names['lim'] ?? 'Uncle Lim'} says the fish are extra fresh today!'),
  ('🎯 A new daily challenge', 'Something new to try at the market today.'),
  ('🫙 Your savings jar', 'A good haggle today puts a little more in your jar.'),
  ('🏆 This week\'s board', 'Your friends are collecting stars. Can you catch up?'),
  (
    '🔋 Boss Raj is calling',
    '${names['raj'] ?? 'Boss Raj'} says: "Best price today only, boss!" (He says that every day.)',
  ),
];

abstract class Reminder {
  /// The phone's notifications (tests swap in a pretend one).
  static Reminder instance = PhoneReminder();

  /// Only in the Android app (the web version can't remind anyone once the tab is closed).
  static bool get supported => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  static const _storage = FlutterSecureStorage();

  /// The player's choice: on or off, and the time (19:00 unless they pick another).
  static Future<({bool on, int hour, int minute})> settings() async {
    try {
      final on = await _storage.read(key: 'reminder') == '1';
      final t = (await _storage.read(key: 'reminder_time') ?? '19:00').split(':');
      return (on: on, hour: int.tryParse(t.first) ?? 19, minute: int.tryParse(t.last) ?? 0);
    } catch (_) {
      return (on: false, hour: 19, minute: 0);
    }
  }

  static Future<void> save({required bool on, required int hour, required int minute}) async {
    try {
      await _storage.write(key: 'reminder', value: on ? '1' : '0');
      await _storage.write(
        key: 'reminder_time',
        value: '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}',
      );
    } catch (_) {}
  }

  /// Asks for permission to notify. False if the player said no.
  Future<bool> allow();

  /// Replaces every planned reminder with [plan] (an empty plan cancels them all).
  Future<void> schedule(List<Nudge> plan);

  /// One notification now (to show it works when switched on).
  Future<void> showNow(String title, String body);
}

class PhoneReminder implements Reminder {
  final _n = FlutterLocalNotificationsPlugin();
  bool _ready = false;
  tz.Location? _sg;

  static const _details = NotificationDetails(
    android: AndroidNotificationDetails(
      'daily',
      'Daily reminder',
      channelDescription: 'One reminder a day to visit the market (you can switch it off in the game\'s Settings).',
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
      icon: 'ic_stat_hh',
    ),
  );

  Future<bool> _init() async {
    if (_ready) return true;
    try {
      tzdata.initializeTimeZones();
      _sg = tz.getLocation('Asia/Singapore');
      await _n.initialize(settings: const InitializationSettings(android: AndroidInitializationSettings('ic_stat_hh')));
      _ready = true;
    } catch (_) {
      _ready = false;
    }
    return _ready;
  }

  AndroidFlutterLocalNotificationsPlugin? get _android =>
      _n.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();

  @override
  Future<bool> allow() async {
    if (!await _init()) return false;
    try {
      final asked = await _android?.requestNotificationsPermission();
      if (asked == false) return false;
      return await _android?.areNotificationsEnabled() ?? true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> schedule(List<Nudge> plan) async {
    if (!await _init()) return;
    try {
      // only the planned ones: a reminder already on the screen stays (cancelAll would remove it too)
      await _n.cancelAllPendingNotifications();
    } catch (_) {}
    for (final (i, x) in plan.indexed) {
      try {
        await _n.zonedSchedule(
          id: 100 + i,
          title: x.title,
          body: x.body,
          scheduledDate: tz.TZDateTime(_sg!, x.at.year, x.at.month, x.at.day, x.at.hour, x.at.minute),
          notificationDetails: _details,
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle, // no exact-alarm permission needed
        );
      } catch (_) {
        // one that can't be planned (say, a moment in the past) never stops the rest
      }
    }
  }

  @override
  Future<void> showNow(String title, String body) async {
    if (!await _init()) return;
    try {
      await _n.show(id: 1, title: title, body: body, notificationDetails: _details);
    } catch (_) {}
  }
}

/// Plans the reminders again from the player's choice and progress (call when the game opens and after a haggle).
Future<void> refreshReminders({required bool playedToday, required Map<String, String> stallNames}) async {
  if (!Reminder.supported) return;
  final s = await Reminder.settings();
  if (!s.on) return Reminder.instance.schedule(const []);
  final now = tz.TZDateTime.now(_sgOrUtc()).toLocalLike();
  await Reminder.instance.schedule(
    planReminders(now: now, hour: s.hour, minute: s.minute, playedToday: playedToday, stallNames: stallNames),
  );
}

tz.Location _sgOrUtc() {
  try {
    tzdata.initializeTimeZones();
    return tz.getLocation('Asia/Singapore');
  } catch (_) {
    return tz.UTC;
  }
}

extension on tz.TZDateTime {
  /// The same wall-clock time as a plain DateTime (the plan works in Singapore wall-clock time).
  DateTime toLocalLike() => DateTime(year, month, day, hour, minute, second);
}
