// Accounts for playing without Tailscale: sign up, wait, get approved; the admin's 👑 Players screen; passwords.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart' hide Fake;
import 'package:hawker_haggle/guide.dart';
import 'package:hawker_haggle/account_screens.dart' show PlayersScreen, statusText;
import 'package:hawker_haggle/accounts.dart';
import 'package:hawker_haggle/api.dart';
import 'package:hawker_haggle/core/game.dart';
import 'package:hawker_haggle/main.dart';
import 'package:hawker_haggle/sfx.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'dart:math' as math;

import 'game_sweep_test.dart' show content;

import 'package:hawker_haggle/screens.dart' show CoopGuestScreen;

import 'widget_test.dart' show Fake, game, settle;

/// A pretend market server with the same rules as server/hh/accounts.py (the server's own tests cover the real one).
class Market {
  final users = <String, Map<String, Object?>>{
    'admin': {'id': 1, 'username': 'admin', 'pw': 'admin', 'status': 'approved', 'admin': true, 'default': true},
  };
  final tokens = <String, String>{};
  final seen = <String>[];
  final saves = <String, Map<String, Object?>>{}; // username: {data, rev}
  final rooms = <String, Map<String, Object?>>{}; // live co-op rooms
  Map<String, Object?> board = {'week': '2026-11-23', 'items': <Object>[], 'gossip': <Object>[]};
  Map<String, Object?> stats = {
    'day': '2026-11-26',
    'players': {'approved': 4, 'pending': 1, 'new_7d': 2, 'active_7d': 3},
    'reach': {'1': 4, '3': 3, '10': 1, '30': 0, 'days_2': 2, 'days_7': 0},
    'stopped': {'after_1': 1, 'after_2_3': 0, 'after_4_10': 0, 'after_11': 0},
    'stopped_last': {'refused': 1},
    'first': {'deal': 3, 'refused': 1},
    'first_bad_gone': 1,
    'style': {'haggles': 40, 'typed': 30, 'tapped': 90, 'together': 2, 'hard': 1},
    'stalls': [
      {
        'id': 'mei',
        'name': 'Auntie Mei',
        'haggles': 20,
        'deals': 19,
        'walked': 1,
        'refused': 0,
        'stars': 50,
        'moves': 80,
      },
      {'id': 'lim', 'name': 'Uncle Lim', 'haggles': 10, 'deals': 3, 'walked': 2, 'refused': 5, 'stars': 4, 'moves': 70},
      {'id': 'raj', 'name': 'Mr Raj', 'haggles': 0, 'deals': 0, 'walked': 0, 'refused': 0, 'stars': 0, 'moves': 0},
    ],
    'ai_today': 12,
  };
  var n = 1;

  Map<String, Object?> pub(Map u) => {
    'username': u['username'],
    'status': u['status'],
    'admin': u['admin'] == true,
    'default_password': u['default'] == true,
  };

  String login(String user) {
    final t = 'hh_${tokens.length + 1}';
    tokens[t] = user;
    return t;
  }

  late final client = MockClient((req) async {
    seen.add(req.url.toString());
    final path = req.url.path;
    final body = req.body.isEmpty ? <String, dynamic>{} : jsonDecode(req.body) as Map<String, dynamic>;
    final tok = (req.headers['Authorization'] ?? '').replaceFirst('Bearer ', '');
    final who = users[tokens[tok]];
    // like the real server: UTF-8 JSON (progress can hold emoji and any language)
    http.Response out(int code, Object data) =>
        http.Response.bytes(utf8.encode(jsonEncode(data)), code, headers: {'content-type': 'application/json'});
    switch (path) {
      case '/ai/accounts/signup':
        final u = '${body['username']}'.toLowerCase();
        if (users.containsKey(u)) return out(409, {'detail': 'That username is taken. Try another one.'});
        users[u] = {'id': ++n, 'username': body['username'], 'pw': body['password'], 'status': 'pending'};
        return out(200, {'token': login(u), ...pub(users[u]!)});
      case '/ai/accounts/login':
        final u = users['${body['username']}'.toLowerCase()];
        if (u == null || u['pw'] != body['password']) return out(401, {'detail': 'Wrong username or password.'});
        return out(200, {'token': login('${u['username']}'.toLowerCase()), ...pub(u)});
      case '/ai/accounts/me':
        return who == null ? out(401, {'detail': 'Please log in again.'}) : out(200, pub(who));
      case '/ai/accounts/logout':
        tokens.remove(tok);
        return out(200, {'ok': true});
      case '/ai/accounts/password':
        if (who == null) return out(401, {'detail': 'Please log in again.'});
        if (who['pw'] != body['old']) return out(403, {'detail': 'Your current password is wrong.'});
        who['pw'] = body['new'];
        who['default'] = false;
        return out(200, {'ok': true});
      case '/ai/accounts/progress':
        if (who == null) return out(401, {'detail': 'Please log in again.'});
        return out(200, saves[tokens[tok]] ?? {'data': null, 'rev': 0});
      case '/ai/accounts/progress/save':
        if (who == null) return out(401, {'detail': 'Please log in again.'});
        final rev = (saves[tokens[tok]]?['rev'] ?? 0) as int;
        if (body['rev'] != rev) return out(409, {'detail': 'Newer progress was saved from another phone.'});
        saves[tokens[tok]!] = {'data': body['data'], 'rev': rev + 1};
        return out(200, {'rev': rev + 1});
      case '/ai/accounts/progress/delete':
        if (who == null) return out(401, {'detail': 'Please log in again.'});
        final had = saves[tokens[tok]];
        if (had == null) return out(200, {'rev': 0});
        saves[tokens[tok]!] = {'data': '', 'rev': (had['rev'] as int) + 1};
        return out(200, {'rev': (had['rev'] as int) + 1});
      case '/ai/coop/create' || '/ai/coop/join' || '/ai/coop/send' || '/ai/coop/pull' || '/ai/coop/leave':
        if (who == null) return out(401, {'detail': 'Log in (Settings > Account) to play together.'});
        final me = tokens[tok]!;
        if (path == '/ai/coop/create') {
          final code = 'AB${rooms.length + 1}CD'.substring(0, 5);
          rooms[code] = {'host': me, 'guest': null, 'stall': body['stall'], 'item': body['item'], 'messages': <Map>[]};
          return out(200, {'code': code});
        }
        final code = '${body['code']}'.toUpperCase();
        final room = rooms[code];
        if (room == null) return out(404, {'detail': 'No room with that code.'});
        final msgs = room['messages'] as List<Map>;
        void add(String from, Map m) => msgs.add({'seq': msgs.length + 1, 'from': from, ...m});
        Map info() => {
          'code': code,
          'host_name': room['host'],
          'guest_name': room['guest'] ?? '',
          'joined': room['guest'] != null,
          'stall': room['stall'],
          'item': room['item'],
        };
        switch (path) {
          case '/ai/coop/join':
            room['guest'] = me;
            add('server', {'type': 'joined', 'name': me});
            return out(200, info());
          case '/ai/coop/send':
            add(room['host'] == me ? 'host' : 'guest', Map<String, Object?>.from(body['msg'] as Map));
            return out(200, {'seq': msgs.length});
          case '/ai/coop/pull':
            final after = (body['after'] ?? 0) as int;
            return out(200, {
              ...info(),
              'you': room['host'] == me ? 'host' : 'guest',
              'messages': [
                for (final m in msgs)
                  if ((m['seq'] as int) > after) m,
              ],
            });
          default:
            if (room['host'] == me) rooms.remove(code);
            return out(200, {'ok': true});
        }
      case '/ai/accounts/board':
        if (who == null) return out(401, {'detail': 'Please log in again.'});
        return out(200, board);
      case '/ai/admin/players':
        if (who?['admin'] != true) return out(403, {'detail': 'Admin only'});
        return out(200, {
          'players': [
            for (final u in users.values.where((u) => u['admin'] != true))
              {
                'id': u['id'],
                'username': u['username'],
                'status': u['status'],
                'created_at': '2026-11-25T01:00:00',
                'ai_today': 0,
              },
          ],
          'ai_today': 0,
          'default_password': who!['default'] == true,
        });
      case '/ai/admin/stats':
        if (who?['admin'] != true) return out(403, {'detail': 'Admin only'});
        return out(200, stats);
      case '/ai/admin/decide':
        if (who?['admin'] != true) return out(403, {'detail': 'Admin only'});
        final u = users.values.firstWhere((u) => u['id'] == body['id']);
        if (body['action'] == 'delete') {
          users.remove('${u['username']}'.toLowerCase());
          return out(200, {'status': 'deleted'});
        }
        if (body['action'] == 'reset') {
          u['pw'] = 'ab12-cd34-ef56';
          return out(200, {'password': 'ab12-cd34-ef56'});
        }
        u['status'] = {'approve': 'approved', 'reject': 'rejected', 'remove': 'removed'}[body['action']];
        return out(200, {'status': u['status']});
    }
    return out(404, {'detail': 'Not Found'});
  });
}

Api apiWith(Market m, {String accountServer = ''}) => Api(
  game: Fake([]),
  content: const {},
  store: MemoryKeyValue(),
  aiHttp: m.client,
  builtInEndpoint: 'https://glm.example/v1',
  builtInModel: 'gx10-current',
  accountServer: accountServer,
);

/// A phone with the real game on it (its progress lives in [store], like secure storage on a real phone).
Api phone(Market m, [MemoryKeyValue? store]) {
  final kv = store ?? MemoryKeyValue();
  return Api(
    game: Game(content: content, store: kv, random: math.Random(4), unlockAll: true, surprises: false),
    content: content,
    store: kv,
    aiHttp: m.client,
    builtInEndpoint: 'https://glm.example/v1',
    builtInModel: 'gx10-current',
    accountServer: 'https://relay.example', // this build's own (Tailscale) market
    syncDelay: const Duration(milliseconds: 1),
  );
}

/// Finish one haggle at Auntie Mei's (the first stall).
Future<void> haggleOnce(Api api) async {
  final s = (content['stalls'] as List).first as Map;
  final g = await api.start('${s['id']}', '${((s['items'] as List).first as Map)['id']}');
  await api.move('${g['id']}', move: 'buy');
}

Future<Map<String, dynamic>> me(Api api) => api.me();

void main() {
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    Sfx.available = false;
    MumGuide.enabled = false;
  });

  test('server addresses are tidied: no scheme, trailing slash or relay path needed', () {
    expect(serverAddress('market.example.com'), 'https://market.example.com');
    expect(serverAddress(' https://market.example.com/ '), 'https://market.example.com');
    expect(serverAddress('https://market.example.com/ai/v1'), 'https://market.example.com');
    expect(serverAddress('http://10.0.0.2:8090/ai/'), 'http://10.0.0.2:8090');
    expect(relayFor('market.example.com'), 'https://market.example.com/ai/v1');
  });

  test('a player signs up, waits, is approved; their login becomes the AI key; logging out goes back', () async {
    final m = Market();
    final api = apiWith(m);
    await api.ensureDevice();
    expect(api.ai.endpoint, 'https://glm.example/v1');
    final acc = await api.signIn(server: 'market.example.com', username: 'JingQi', password: 'kopi1234', signUp: true);
    expect(acc.status, 'pending');
    expect(api.ai.endpoint, 'https://market.example.com/ai/v1');
    expect(api.ai.apiKey, acc.token);
    expect(api.ai.model, 'gx10-current');
    m.users['jingqi']!['status'] = 'approved';
    expect((await api.refreshAccount())!.status, 'approved');
    await expectLater(
      api.signIn(server: 'market.example.com', username: 'jingqi', password: 'x', signUp: true),
      throwsA(isA<AccountError>().having((e) => e.message, 'message', contains('taken'))),
    );
    await api.signOut();
    expect(api.account, isNull);
    expect(api.ai.endpoint, 'https://glm.example/v1');
    expect(api.ai.apiKey, '');
  });

  test('logged out on the server (e.g. removed): logged out here too', () async {
    final m = Market();
    final api = apiWith(m);
    await api.signIn(server: 'market.example.com', username: 'ahboy', password: 'secret12', signUp: true);
    m.tokens.clear();
    await expectLater(api.refreshAccount(), throwsA(isA<AccountError>()));
    expect(api.account, isNull);
    expect(api.ai.endpoint, 'https://glm.example/v1');
  });

  test('the admin logs in (the AI goes through the market) and can change the default password', () async {
    final m = Market();
    final api = apiWith(m, accountServer: 'https://relay.example');
    await api.ensureDevice();
    final acc = await api.signIn(server: api.accountServer, username: 'admin', password: 'admin');
    expect(acc.admin, isTrue);
    expect(acc.defaultPassword, isTrue);
    expect(api.ai.endpoint, 'https://relay.example/ai/v1'); // through the market, with the admin's login
    await expectLater(api.changePassword('wrong', 'new-pass-1'), throwsA(isA<AccountError>()));
    await api.changePassword('admin', 'new-pass-1');
    expect(api.account!.defaultPassword, isFalse);
    expect(m.users['admin']!['pw'], 'new-pass-1');
  });

  testWidgets('Settings: sign up, see "waiting", then approved after Check again', (tester) async {
    final m = Market();
    final api = apiWith(m, accountServer: 'https://market.example.com');
    await tester.pumpWidget(HawkerHaggleApp(api: api));
    await settle(tester, 2000);
    await tester.tap(find.byIcon(Icons.settings_rounded));
    await settle(tester);
    await tester.dragUntilVisible(
      find.byKey(const ValueKey('account_open')),
      find.byType(ListView).last,
      const Offset(0, -200),
    );
    await tester.ensureVisible(find.byKey(const ValueKey('account_open')));
    await settle(tester, 300);
    await tester.tap(find.byKey(const ValueKey('account_open')));
    await settle(tester, 600);
    expect(find.text('https://market.example.com'), findsOneWidget); // the build's market, ready
    await tester.enterText(find.byKey(const ValueKey('acc_user')), 'Jing Qi!'); // only allowed characters stay
    await tester.enterText(find.byKey(const ValueKey('acc_pw')), 'kopi1234');
    await tester.tap(find.byKey(const ValueKey('acc_signup')));
    await settle(tester, 1200);
    expect(m.users.containsKey('jingqi'), isTrue);
    expect(find.text('Logged in as JingQi'), findsOneWidget);
    expect(find.text(statusText('pending')), findsWidgets);
    expect(api.ai.endpoint, 'https://market.example.com/ai/v1'); // the game's AI now goes to the market
    m.users['jingqi']!['status'] = 'approved';
    await tester.ensureVisible(find.text('Check again'));
    await tester.tap(find.text('Check again'));
    await settle(tester, 800);
    expect(find.text(statusText('approved')), findsOneWidget);
    await settle(tester, 4000);
  });

  testWidgets('wrong password shows the reason in the dialog', (tester) async {
    final m = Market();
    final api = apiWith(m, accountServer: 'https://market.example.com');
    await tester.pumpWidget(HawkerHaggleApp(api: api));
    await settle(tester, 2000);
    await tester.tap(find.byIcon(Icons.settings_rounded));
    await settle(tester);
    await tester.dragUntilVisible(
      find.byKey(const ValueKey('account_open')),
      find.byType(ListView).last,
      const Offset(0, -200),
    );
    await tester.ensureVisible(find.byKey(const ValueKey('account_open')));
    await settle(tester, 300);
    await tester.tap(find.byKey(const ValueKey('account_open')));
    await settle(tester, 600);
    await tester.enterText(find.byKey(const ValueKey('acc_user')), 'admin');
    await tester.enterText(find.byKey(const ValueKey('acc_pw')), 'nope');
    await tester.tap(find.byKey(const ValueKey('acc_login')));
    await settle(tester, 800);
    expect(find.text('Wrong username or password.'), findsOneWidget);
    expect(api.account, isNull);
    await settle(tester, 4000);
  });

  testWidgets('admin: 👑 Players shows sign-ups; approve, reset a password; default-password warning goes away', (
    tester,
  ) async {
    final m = Market();
    m.users['ahboy'] = {'id': 7, 'username': 'ahboy', 'pw': 'x', 'status': 'pending'};
    final api = apiWith(m, accountServer: 'https://relay.example');
    await api.signIn(server: api.accountServer, username: 'admin', password: 'admin');
    await tester.pumpWidget(HawkerHaggleApp(api: api));
    await settle(tester, 2000);
    await tester.tap(find.byIcon(Icons.settings_rounded));
    await settle(tester);
    await tester.dragUntilVisible(
      find.byKey(const ValueKey('players_open')),
      find.byType(ListView).last,
      const Offset(0, -200),
    );
    await tester.ensureVisible(find.byKey(const ValueKey('players_open')));
    await settle(tester, 300);
    expect(find.text('Logged in as admin 👑'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('players_open')));
    await settle(tester, 1000);
    expect(find.byKey(const ValueKey('default_pw_warning')), findsOneWidget);
    expect(find.text('1 waiting · 1 in all · 0 AI chats today'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('approve_ahboy')));
    await settle(tester, 1000);
    expect(m.users['ahboy']!['status'], 'approved');
    expect(find.byKey(const ValueKey('remove_ahboy')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('more_ahboy')));
    await settle(tester, 600);
    await tester.tap(find.text('Give a new password'));
    await settle(tester, 1000);
    expect(find.text('ab12-cd34-ef56'), findsOneWidget);
    await tester.tap(find.text('Copy'));
    await settle(tester, 600);
    // delete for good, after a confirmation
    await tester.tap(find.byKey(const ValueKey('more_ahboy')));
    await settle(tester, 600);
    await tester.tap(find.text('Delete account'));
    await settle(tester, 600);
    expect(find.text('Delete ahboy?'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('delete_confirm')));
    await settle(tester, 1000);
    expect(m.users.containsKey('ahboy'), isFalse);
    expect(find.byKey(const ValueKey('more_ahboy')), findsNothing);
    // change the default password from the warning
    await tester.tap(find.text('Change password'));
    await settle(tester, 600);
    await tester.enterText(find.byKey(const ValueKey('pw_old')), 'admin');
    await tester.enterText(find.byKey(const ValueKey('pw_new')), 'teh-tarik-88');
    await tester.enterText(find.byKey(const ValueKey('pw_again')), 'teh-tarik-8');
    await tester.tap(find.byKey(const ValueKey('pw_save')));
    await settle(tester, 600);
    expect(find.text("The new passwords don't match."), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('pw_again')), 'teh-tarik-88');
    await tester.tap(find.byKey(const ValueKey('pw_save')));
    await settle(tester, 1200);
    expect(m.users['admin']!['pw'], 'teh-tarik-88');
    expect(find.byKey(const ValueKey('default_pw_warning')), findsNothing);
    await settle(tester, 4000);
  });

  group('progress follows the account', () {
    test('a new account starts fresh if you say so; another phone sees it; logging out brings yours back', () async {
      final m = Market();
      final a = phone(m);
      await a.setName('Guest Me');
      await haggleOnce(a);
      expect((await me(a))['haggles'], 1);
      int? asked;
      await a.signIn(
        server: 'market.example.com',
        username: 'JingQi',
        password: 'kopi1234',
        signUp: true,
        bringProgress: (n) async {
          asked = n;
          return false;
        },
      );
      expect(asked, 1);
      expect((await me(a))['haggles'], 0); // the new account's own (empty) progress
      expect((await me(a))['named'], isFalse); // so the market asks for a name
      await a.setName('Jing Qi');
      await haggleOnce(a);
      await a.syncNow();
      expect(a.progressSaved, isTrue);
      expect('${m.saves['jingqi']!['data']}', contains('Jing Qi'));

      // another phone, same account: same progress, no question asked
      final b = phone(m);
      await b.setName('Someone Else');
      await b.signIn(
        server: 'market.example.com',
        username: 'jingqi',
        password: 'kopi1234',
        bringProgress: (_) async => fail('the account already has progress'),
      );
      expect((await me(b))['name'], 'Jing Qi');
      expect((await me(b))['haggles'], 1);

      // log out: this phone's own progress again
      await a.signOut();
      expect((await me(a))['name'], 'Guest Me');
      expect((await me(a))['haggles'], 1);
      await b.signOut();
      expect((await me(b))['name'], 'Someone Else');
    });

    test('or bring this phone\'s progress into the new account (the phone keeps its own copy)', () async {
      final m = Market();
      final a = phone(m);
      await a.setName('Ah Boy');
      await haggleOnce(a);
      await a.signIn(
        server: 'market.example.com',
        username: 'ahboy',
        password: 'kopi1234',
        signUp: true,
        bringProgress: (_) async => true,
      );
      expect((await me(a))['name'], 'Ah Boy');
      expect((await me(a))['haggles'], 1);
      await haggleOnce(a);
      await a.syncNow();
      expect(jsonDecode('${m.saves['ahboy']!['data']}')['haggles'], hasLength(2));
      await a.signOut();
      expect((await me(a))['haggles'], 1); // the guest progress didn't move
    });

    test('an empty phone just starts the account fresh without asking', () async {
      final m = Market();
      final a = phone(m);
      await a.signIn(
        server: 'market.example.com',
        username: 'newbie',
        password: 'kopi1234',
        signUp: true,
        bringProgress: (_) async => fail('nothing to bring'),
      );
      expect((await me(a))['haggles'], 0);
      expect(m.saves['newbie']!['rev'], 1);
    });

    test('the account\'s progress is still there after the app restarts, and picks up the newest copy', () async {
      final m = Market();
      final store = MemoryKeyValue();
      final a = phone(m, store);
      await a.signIn(server: 'market.example.com', username: 'jingqi', password: 'kopi1234', signUp: true);
      await a.setName('Jing Qi');
      await a.syncNow();
      // meanwhile another phone plays a haggle on the same account
      final b = phone(m);
      await b.signIn(server: 'market.example.com', username: 'jingqi', password: 'kopi1234');
      await haggleOnce(b);
      await b.syncNow();
      final again = phone(m, store); // the app opens again
      expect((await me(again))['name'], 'Jing Qi');
      expect((await me(again))['haggles'], 1);
    });

    test('two phones at once: the older one takes the newer progress instead of overwriting it', () async {
      final m = Market();
      final a = phone(m), b = phone(m);
      await a.signIn(server: 'market.example.com', username: 'jingqi', password: 'kopi1234', signUp: true);
      await b.signIn(server: 'market.example.com', username: 'jingqi', password: 'kopi1234');
      await b.setName('From B');
      await b.syncNow();
      await a.setName('From A'); // A hasn't seen B's save
      await a.syncNow();
      expect((await me(a))['name'], 'From B');
      expect('${m.saves['jingqi']!['data']}', contains('From B'));
    });

    test('delete my data while logged in clears the account copy too', () async {
      final m = Market();
      final a = phone(m);
      await a.setName('Guest Me');
      await haggleOnce(a);
      await a.signIn(
        server: 'market.example.com',
        username: 'jingqi',
        password: 'kopi1234',
        signUp: true,
        bringProgress: (_) async => true,
      );
      await a.syncNow();
      await a.deleteMe();
      await a.syncNow();
      expect((await me(a))['haggles'], 0);
      expect(jsonDecode('${m.saves['jingqi']!['data']}')['haggles'], isEmpty);
      await a.signOut();
      expect((await me(a))['haggles'], 0); // this phone's own copy went too
    });

    test('logged in on an older version: logged out once, so logging in again asks properly', () async {
      final m = Market();
      final store = MemoryKeyValue();
      final old = phone(m, store);
      await old.setName('Caspar');
      await haggleOnce(old);
      // what an older version left behind: logged in, but the progress never moved
      final t = m.login('arella');
      m.users['arella'] = {'id': 9, 'username': 'Arella', 'pw': 'x', 'status': 'pending'};
      await store.write(
        'account',
        jsonEncode(
          Account(server: 'https://market.example.com', username: 'Arella', token: t, status: 'pending').toJson(),
        ),
      );
      await store.write('ai_key', t);
      final now = phone(m, store);
      await now.ensureDevice();
      expect(now.account, isNull);
      expect(now.ai.apiKey, '');
      expect((await me(now))['name'], 'Caspar'); // nothing moved
      expect((await me(now))['haggles'], 1);
      expect(m.saves, isEmpty);
    });

    test(
      'admin progress follows the admin account too (from your own phone, the question; elsewhere, the same)',
      () async {
        final m = Market();
        // the owner tries a fresh browser first: nothing to bring, so the admin account starts empty
        final incognito = phone(m);
        await incognito.signIn(
          server: 'relay.example',
          username: 'admin',
          password: 'admin',
          bringProgress: (_) async => fail('nothing to bring'),
        );
        expect(incognito.ai.endpoint, 'https://relay.example/ai/v1'); // through the market, like a player's
        // then on their own phone, with real progress: the empty admin copy doesn't count, so it asks
        final mine = phone(m);
        await mine.setName('Caspar');
        await haggleOnce(mine);
        int? asked;
        await mine.signIn(
          server: 'relay.example',
          username: 'admin',
          password: 'admin',
          bringProgress: (n) async {
            asked = n;
            return true;
          },
        );
        expect(asked, 1);
        expect((await me(mine))['name'], 'Caspar');
        await mine.syncNow();
        // back in the fresh browser: log in again and it's Caspar's progress
        await incognito.signOut();
        await incognito.signIn(server: 'relay.example', username: 'admin', password: 'admin');
        expect((await me(incognito))['name'], 'Caspar');
        expect((await me(incognito))['haggles'], 1);
      },
    );
  });

  test('the board feeds the stallholders\' gossip', () async {
    final m = Market()
      ..board = {
        'week': '2026-11-23',
        'items': [
          {
            'stall': 'mei',
            'item': 'durian',
            'players': 1,
            'top': [
              {'name': 'Arella', 'price': 19, 'you': false},
            ],
            'you': null,
          },
        ],
        'gossip': [
          {'stall': 'mei', 'item': 'durian', 'name': 'Arella', 'day': '2026-11-25'},
        ],
      };
    final a = phone(m);
    expect(await a.board(), isNull); // not logged in
    await a.signIn(server: 'market.example.com', username: 'jingqi', password: 'kopi1234', signUp: true);
    final b = await a.board();
    expect((b!['items'] as List).single['top'][0]['name'], 'Arella');
    final r = await a.start('mei', 'mango', 'none');
    expect('${r['line']}', startsWith('Eh, your friend Arella came by also!'));
  });

  testWidgets('the market shows the board when logged in; Beat it starts that item with the target', (tester) async {
    final m = Market()
      ..board = {
        'week': '2026-11-23',
        'items': [
          {
            'stall': 'mei',
            'item': 'mango',
            'players': 1,
            'top': [
              {'name': 'Arella', 'price': 11, 'you': false},
            ],
            'you': null,
          },
        ],
        'gossip': <Object>[],
        'hagglers': [
          {'name': 'Arella', 'stars': 9, 'items': 4, 'deals': 6, 'you': false, 'place': 1},
          for (var i = 2; i <= 10; i++)
            {'name': 'Player $i', 'stars': 9 - i ~/ 2, 'items': 3, 'deals': 3, 'you': false, 'place': i},
          {'name': 'jingqi', 'stars': 1, 'items': 1, 'deals': 1, 'you': true, 'place': 14},
        ],
      };
    final api = apiWith(m, accountServer: 'https://market.example.com');
    await api.signIn(server: api.accountServer, username: 'jingqi', password: 'kopi1234', signUp: true);
    await tester.pumpWidget(HawkerHaggleApp(api: api));
    await settle(tester, 2000);
    await tester.tap(find.byKey(const ValueKey('tab_friends')));
    await settle(tester);
    expect(find.byKey(const ValueKey('board_open')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('board_open')));
    await settle(tester, 1000);
    // top hagglers first: the stars, and you at the end even outside the top 10
    expect(find.text('Arella'), findsOneWidget);
    expect(find.text('9 ⭐'), findsOneWidget);
    await tester.dragUntilVisible(
      find.byKey(const ValueKey('haggler_14')),
      find.byType(ListView).last,
      const Offset(0, -200),
    );
    expect(find.text('jingqi (you)'), findsOneWidget);
    expect(find.text('#14'), findsOneWidget);
    expect(find.text('⋯'), findsOneWidget); // a gap before you
    await tester.tap(find.byKey(const ValueKey('tab_prices')));
    await settle(tester, 800);
    expect(find.text('🥇 Arella  \$11'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('beat_mei_mango')));
    await settle(tester, 1500);
    expect(find.text("🏆 Beat Arella's \$11!"), findsOneWidget);
    await settle(tester, 3000);
  });

  testWidgets('an older market server has no top hagglers yet: the tab says so', (tester) async {
    final m = Market();
    final api = apiWith(m, accountServer: 'https://market.example.com');
    await api.signIn(server: api.accountServer, username: 'jingqi', password: 'kopi1234', signUp: true);
    await tester.pumpWidget(HawkerHaggleApp(api: api));
    await settle(tester, 2000);
    await tester.tap(find.byKey(const ValueKey('tab_friends')));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('board_open')));
    await settle(tester, 1000);
    expect(find.textContaining('being updated'), findsOneWidget);
  });

  testWidgets('admin: 📊 how players play, from the Players screen', (tester) async {
    final m = Market();
    final api = apiWith(m, accountServer: 'https://relay.example');
    await api.signIn(server: api.accountServer, username: 'admin', password: 'admin');
    await tester.pumpWidget(MaterialApp(home: PlayersScreen(api: api)));
    await settle(tester, 1000);
    await tester.tap(find.byKey(const ValueKey('stats_open')));
    await settle(tester, 1000);
    expect(find.text('📊 How players play'), findsOneWidget);
    expect(find.text('3  (60%)'), findsOneWidget); // played 3 or more: 3 of 5 players
    expect(find.text('AI calls today (everyone)'), findsOneWidget);
    await tester.dragUntilVisible(
      find.byKey(const ValueKey('stats_stall_lim')),
      find.byType(ListView).last,
      const Offset(0, -200),
    );
    expect(find.text('Uncle Lim  😣 hard?'), findsOneWidget);
    expect(find.text('Auntie Mei  😴 easy?'), findsOneWidget);
    await tester.dragUntilVisible(
      find.textContaining('Only players with an account'),
      find.byType(ListView).last,
      const Offset(0, -300),
    );
    expect(find.text('Nobody has haggled here yet.'), findsOneWidget);
    expect(find.text('25%'), findsOneWidget); // typed: 30 of 120 moves
  });

  test('only the admin can ask for the stats', () async {
    final m = Market();
    final a = apiWith(m, accountServer: 'https://relay.example');
    await expectLater(a.stats(), throwsA(isA<AccountError>()));
    await a.signIn(server: 'market.example.com', username: 'jingqi', password: 'kopi1234', signUp: true);
    await expectLater(a.stats(), throwsA(isA<AccountError>()));
  });

  test("the admin's AI goes through the market it logged in to, like a player's; logging out goes back", () async {
    final m = Market();
    final a = apiWith(m, accountServer: 'https://relay.example');
    final acc = await a.signIn(server: 'ai.labhost.example', username: 'admin', password: 'admin');
    expect(acc.admin, isTrue);
    expect(a.ai.endpoint, 'https://ai.labhost.example/ai/v1');
    expect(a.ai.apiKey, acc.token);
    await a.signOut();
    expect(a.ai.endpoint, 'https://glm.example/v1');
  });

  group('live co-op', () {
    test('two phones: create, join, a move from the friend, the state back', () async {
      final m = Market();
      final host = apiWith(m), friend = apiWith(m);
      await expectLater(host.coopCreate('mei', 'mango'), throwsA(isA<AccountError>())); // log in first
      await host.signIn(server: 'market.example.com', username: 'Arella', password: 'kopi1234', signUp: true);
      await friend.signIn(server: 'market.example.com', username: 'Melody', password: 'kopi1234', signUp: true);
      final code = await host.coopCreate('mei', 'mango');
      final room = await friend.coopJoin(code.toLowerCase());
      expect(room['host_name'], 'arella');
      await friend.coopSend(code, {'type': 'move', 'text': '12 can?'});
      final got = await host.coopPull(code, 0);
      expect([for (final x in (got['messages'] as List).cast<Map>()) x['type']], ['joined', 'move']);
      await host.coopSend(code, {
        'type': 'state',
        'view': {'line': 'Aiyo, 16 lah'},
      });
      final seen = await friend.coopPull(code, 2);
      expect(((seen['messages'] as List).single as Map)['view'], {'line': 'Aiyo, 16 lah'});
      await host.coopLeave(code);
      await expectLater(friend.coopPull(code, 0), throwsA(isA<AccountError>()));
    });

    testWidgets("the host's phone plays the friend's move, says who it was, and sends the state back", (tester) async {
      final m = Market();
      final fake = Fake([
        {
          ...{
            'id': 'g1',
            'stall': 'mei',
            'item': 'mango',
            'event': 'counter',
            'line': 'Your friend so cute! \$16 lah.',
            'ai_line': false,
            'ask': 16,
            'opening': 18,
            'patience': 70,
            'mood': 0,
            'qty': 1,
            'done': false,
            'result': '',
            'deal': null,
            'pending': null,
            'stars': 0,
            'saved': 0.0,
            'suggestions': [
              {'move': 'offer', 'price': 12.0, 'text': '\$12 can?'},
            ],
            'surprise': '',
            'surprise_note': '',
            'hearts': 0,
            'new_stickers': <Object>[],
            'notes': <Object>[],
            'accept_text': 'OK lah, \$16',
            'walk_text': 'Bye',
          },
        },
      ]);
      final api = Api(
        game: fake,
        content: const {},
        store: MemoryKeyValue(),
        aiHttp: m.client,
        builtInEndpoint: 'https://glm.example/v1',
        builtInModel: 'gx10-current',
        accountServer: 'https://market.example.com',
      );
      await api.signIn(server: api.accountServer, username: 'Arella', password: 'kopi1234', signUp: true);
      await tester.binding.setSurfaceSize(const Size(420, 1600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(HawkerHaggleApp(api: api));
      await settle(tester, 2000);
      await tester.ensureVisible(find.text('box of mangoes'));
      await tester.tap(find.text('box of mangoes'));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('coop_invite')));
      await settle(tester, 800);
      final code = m.rooms.keys.single;
      expect(find.text(code), findsOneWidget);
      await tester.tap(find.text('OK'));
      await settle(tester, 400);
      // the friend joins (on their phone) and types a message
      final friend = apiWith(m);
      await friend.signIn(server: 'market.example.com', username: 'Melody', password: 'kopi1234', signUp: true);
      await friend.coopJoin(code);
      await friend.coopSend(code, {'type': 'move', 'text': 'auntie my friend very poor one'});
      await tester.pump(const Duration(milliseconds: 1600)); // the host checks the room
      await settle(tester, 2500);
      expect(fake.sent.last, {'text': 'auntie my friend very poor one', 'friend': 'melody'});
      expect(find.text('👥 melody: auntie my friend very poor one'), findsOneWidget);
      final states = [
        for (final x in (m.rooms[code]!['messages'] as List<Map>))
          if (x['type'] == 'state') x,
      ];
      expect(states, isNotEmpty);
      expect((states.last['view'] as Map)['line'], 'Your friend so cute! \$16 lah.');
      expect(states.last['chat'], isA<List>());
      await tester.pumpWidget(const SizedBox()); // leave: timers stop, the room closes
      await settle(tester, 300);
      expect(m.rooms, isEmpty);
    });

    List<Map> roomMsgs(Market m, String code, String type) => [
      for (final x in (m.rooms[code]!['messages'] as List<Map>))
        if (x['type'] == type) x,
    ];

    testWidgets("talking at the same time: a friend's move made on an old turn isn't played, and whispers stay "
        'between the two of you', (tester) async {
      final m = Market();
      final fake = Fake([
        game('Hmm, \$16 lah.', event: 'counter', ask: 16),
        game('OK \$15.', event: 'counter', ask: 15),
      ]);
      final api = Api(
        game: fake,
        content: const {},
        store: MemoryKeyValue(),
        aiHttp: m.client,
        builtInEndpoint: 'https://glm.example/v1',
        builtInModel: 'gx10-current',
        accountServer: 'https://market.example.com',
      );
      await api.signIn(server: api.accountServer, username: 'Arella', password: 'kopi1234', signUp: true);
      await tester.binding.setSurfaceSize(const Size(420, 1600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(HawkerHaggleApp(api: api));
      await settle(tester, 2000);
      await tester.ensureVisible(find.text('box of mangoes'));
      await tester.tap(find.text('box of mangoes'));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('coop_invite')));
      await settle(tester, 800);
      final code = m.rooms.keys.single;
      await tester.tap(find.text('OK'));
      await settle(tester, 400);
      final friend = apiWith(m);
      await friend.signIn(server: 'market.example.com', username: 'Melody', password: 'kopi1234', signUp: true);
      await friend.coopJoin(code);
      await tester.pump(const Duration(milliseconds: 1600));
      await settle(tester, 1000);
      final turn = ((roomMsgs(m, code, 'state').last['view'] as Map)['turn'] as num).toInt();
      // both of the friend's moves were made on the same turn: the first is played, the second came too late
      await friend.coopSend(code, {'type': 'move', 'pick': 0, 'at': turn});
      await friend.coopSend(code, {'type': 'move', 'text': '\$12 can?', 'at': turn});
      await friend.coopSend(code, {'type': 'whisper', 'say': 'firm'});
      await tester.pump(const Duration(milliseconds: 1600));
      await settle(tester, 2500);
      expect(fake.sent, [
        {'pick': 0, 'friend': 'melody'},
      ]);
      expect(find.textContaining('one at a time lah'), findsOneWidget);
      final last = roomMsgs(m, code, 'state').last['view'] as Map;
      expect(last['bounced'], 1); // the friend's phone gets the new state at once (no waiting on "typing…")
      expect(last['turn'], turn + 1);
      expect(find.byKey(const ValueKey('whisper_heard')), findsOneWidget);
      expect(find.textContaining('Go firm now!'), findsOneWidget);
      // the host whispers back; a move from an older app (no turn) is played as before
      await tester.tap(find.byKey(const ValueKey('whisper_open')));
      await settle(tester, 600);
      await tester.tap(find.byKey(const ValueKey('whisper:wait')));
      await settle(tester, 600);
      expect(roomMsgs(m, code, 'whisper').last, containsPair('say', 'wait'));
      await friend.coopSend(code, {'type': 'move', 'text': 'auntie please'});
      await tester.pump(const Duration(milliseconds: 1600));
      await settle(tester, 2500);
      expect(fake.sent.last, {'text': 'auntie please', 'friend': 'melody'});
      expect(fake.sent.length, 2); // whispers never reach the stallholder
      await tester.pumpWidget(const SizedBox());
      await settle(tester, 300);
    });

    testWidgets("the friend's phone: moves carry the turn, the host's whisper shows, and the friend gets their own "
        'share of the deal (once)', (tester) async {
      final m = Market();
      final guest = _Guest();
      final api = Api(
        game: guest,
        content: const {},
        store: MemoryKeyValue(),
        aiHttp: m.client,
        builtInEndpoint: 'https://glm.example/v1',
        builtInModel: 'gx10-current',
        accountServer: 'https://market.example.com',
      );
      final host = apiWith(m);
      await host.signIn(server: 'market.example.com', username: 'Arella', password: 'kopi1234', signUp: true);
      await api.signIn(server: api.accountServer, username: 'Melody', password: 'kopi1234', signUp: true);
      final code = await host.coopCreate('mei', 'mango');
      final room = await api.coopJoin(code);
      final stall = (guest.stalls()['stalls'] as List).first as Map;
      await tester.binding.setSurfaceSize(const Size(420, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          home: CoopGuestScreen(api: api, code: code, room: room, stall: stall),
        ),
      );
      await host.coopSend(code, {
        'type': 'state',
        'view': {...game('\$16 lah.', ask: 16), 'turn': 3, 'bounced': 0},
        'chat': <Object>[],
      });
      await tester.pump(const Duration(milliseconds: 1600));
      await settle(tester, 800);
      await tester.tap(find.text('\$11 can or not?'));
      await settle(tester, 600);
      expect(roomMsgs(m, code, 'move').last, containsPair('at', 3));
      // the host moved first: the friend's move bounced, they're told and can choose again
      await host.coopSend(code, {
        'type': 'state',
        'view': {...game('\$15 lah.', ask: 15), 'turn': 4, 'bounced': 1},
        'chat': <Object>[],
      });
      await host.coopSend(code, {'type': 'whisper', 'say': 'deal'});
      await tester.pump(const Duration(milliseconds: 1600));
      await settle(tester, 800);
      expect(find.textContaining('one at a time lah'), findsOneWidget);
      expect(find.textContaining('Take the deal!'), findsWidgets);
      // the deal closes; the state may come twice, but the friend's share is counted once
      final done = {
        ...game('Deal!', result: 'deal', deal: 14, stars: 3, saved: 0.22),
        'turn': 5,
        'bounced': 1,
        'moves': 4,
      };
      await host.coopSend(code, {'type': 'state', 'view': done, 'chat': <Object>[]});
      await host.coopSend(code, {'type': 'state', 'view': done, 'chat': <Object>[]});
      await tester.pump(const Duration(milliseconds: 1600));
      await settle(tester, 1200);
      expect(guest.finished, 1);
      expect(guest.view?['deal'], 14);
      expect(guest.tapped, 1);
      expect(find.byKey(const ValueKey('coop_stars')), findsOneWidget);
      expect(find.textContaining('into your savings jar'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await settle(tester, 300);
    });

    test("coopFinish puts the friend's share into their own progress: the haggle, stars, jar and Teamwork", () async {
      final m = Market();
      final api = phone(m);
      final s = (content['stalls'] as List).first as Map;
      final item = (s['items'] as List).first as Map;
      final ask = (item['ask'] as num).toDouble();
      final before = (await api.me())['haggles'] as num;
      final r = await api.coopFinish(
        stall: '${s['id']}',
        item: '${item['id']}',
        view: {'result': 'deal', 'deal': ask - 3, 'opening': ask, 'stars': 3, 'saved': 0.2, 'qty': 1, 'moves': 5},
        host: 'arella',
        typed: 2,
      );
      expect((await api.me())['haggles'], before + 1);
      expect(r['stickers'], containsAll(['first_deal', 'three_stars', 'teamwork']));
      expect((r['notes'] as List).join(' '), contains('into your savings jar'));
      expect(((await api.me())['stars'] as num) >= 3, isTrue);
    });
  });
}

/// The friend's phone: counts its share of a co-op haggle instead of saving it.
class _Guest extends Fake {
  _Guest() : super([]);
  int finished = 0;
  Map? view;
  int tapped = 0;
  @override
  Future<Map<String, Object?>> coopFinish({
    required String stall,
    required String item,
    required Map view,
    String host = '',
    int typed = 0,
    int tapped = 0,
  }) async {
    finished++;
    this.view = view;
    this.tapped = tapped;
    return {
      'stickers': ['teamwork'],
      'mum': null,
      'unlocked': <String>[],
      'notes': ['🫙 \$4 into your savings jar (\$4 saved).'],
    };
  }
}
