// Settings > Account: sign up / log in to the market's server (for playing without Tailscale), change your password,
// and for the admin, the 👑 Players screen to approve people.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'accounts.dart';
import 'api.dart';
import 'widgets.dart';

InputDecoration _box(String label, {Widget? suffix}) => InputDecoration(
  labelText: label,
  filled: true,
  fillColor: Colors.white,
  suffixIcon: suffix,
  border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
);

const _title = TextStyle(fontSize: 20, fontWeight: FontWeight.w700);

String statusText(String s) => switch (s) {
  'approved' => '✅ Approved: the stallholders chat with AI',
  'pending' => '⏳ Waiting for the admin to approve you',
  'rejected' => '❌ Not approved',
  'removed' => '🚫 Removed by the admin',
  _ => s,
};

/// The Account part of Settings.
class AccountSection extends StatefulWidget {
  const AccountSection({super.key, required this.api, required this.onAiChanged});
  final Api api;
  final VoidCallback onAiChanged;
  @override
  State<AccountSection> createState() => _AccountSectionState();
}

class _AccountSectionState extends State<AccountSection> {
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    if (widget.api.account != null) _refresh(quiet: true);
  }

  void _toast(String m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  Future<void> _refresh({bool quiet = false}) async {
    setState(() => _busy = true);
    try {
      await widget.api.refreshAccount();
    } on AccountError catch (e) {
      if (!quiet && mounted) _toast(e.message);
      if (e.code == 401) widget.onAiChanged();
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final api = widget.api;
    final a = api.account;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Account', style: _title),
        const SizedBox(height: 6),
        if (a == null) ...[
          const Text(
            'Playing without Tailscale? Make an account on the market server. Once the admin approves you, the '
            'stallholders chat with AI. (On Tailscale you don\'t need one.) Your progress is kept on your account, '
            'so any phone you log in on shows it.',
            style: TextStyle(height: 1.4, color: Palette.soft),
          ),
          const SizedBox(height: 10),
          Bouncy(
            key: const ValueKey('account_open'),
            onTap: () async {
              final acc = await showDialog<Account>(
                context: context,
                builder: (_) => SignInDialog(api: api),
              );
              if (acc == null || !mounted) return;
              setState(() {});
              widget.onAiChanged();
              _toast(acc.admin ? 'Welcome back, admin 👑' : statusText(acc.status));
            },
            child: const Pill(text: 'Sign up / Log in', icon: '🔑', color: Palette.gold),
          ),
        ] else ...[
          Text(
            'Logged in as ${a.username}${a.admin ? ' 👑' : ''}',
            key: const ValueKey('account_who'),
            style: const TextStyle(fontWeight: FontWeight.w700, color: Palette.ink),
          ),
          const SizedBox(height: 2),
          Text(a.server, style: const TextStyle(color: Palette.soft, fontSize: 12)),
          if (!a.admin) ...[
            const SizedBox(height: 4),
            Text(statusText(a.status), key: const ValueKey('account_status')),
            const SizedBox(height: 2),
            Text(
              api.progressSaved
                  ? '☁️ Your progress is kept on this account'
                  : '☁️ Your progress will be saved to this account when the market server can be reached',
              key: const ValueKey('account_progress'),
              style: const TextStyle(color: Palette.soft, fontSize: 13),
            ),
          ],
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (a.admin)
                Bouncy(
                  key: const ValueKey('players_open'),
                  onTap: () async {
                    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => PlayersScreen(api: api)));
                    if (mounted) setState(() {});
                  },
                  child: const Pill(text: 'Players', icon: '👑', color: Palette.gold),
                ),
              if (!a.admin)
                Bouncy(
                  enabled: !_busy,
                  onTap: _refresh,
                  child: Pill(text: _busy ? 'Checking…' : 'Check again', icon: '🔄'),
                ),
              Bouncy(
                key: const ValueKey('password_open'),
                onTap: () async {
                  final ok = await showDialog<bool>(
                    context: context,
                    builder: (_) => PasswordDialog(api: api),
                  );
                  if (ok == true && mounted) {
                    setState(() {});
                    _toast('Password changed.');
                  }
                },
                child: const Pill(text: 'Change password', icon: '🔒'),
              ),
              Bouncy(
                onTap: () async {
                  await api.signOut();
                  if (!mounted) return;
                  setState(() {});
                  widget.onAiChanged();
                  _toast('Logged out.');
                },
                child: const Pill(text: 'Log out', icon: '👋'),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

class SignInDialog extends StatefulWidget {
  const SignInDialog({super.key, required this.api});
  final Api api;
  @override
  State<SignInDialog> createState() => _SignInDialogState();
}

class _SignInDialogState extends State<SignInDialog> {
  late final _server = TextEditingController(text: widget.api.accountServer);
  final _user = TextEditingController();
  final _pw = TextEditingController();
  bool _show = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _server.dispose();
    _user.dispose();
    _pw.dispose();
    super.dispose();
  }

  Future<void> _go({required bool signUp}) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final acc = await widget.api.signIn(
        server: _server.text,
        username: _user.text,
        password: _pw.text,
        signUp: signUp,
        bringProgress: _askBring,
      );
      if (mounted) Navigator.of(context).pop(acc);
    } on AccountError catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = e.message;
        });
      }
    }
  }

  /// The account has no progress yet and this phone has some: start fresh, or bring it along?
  Future<bool> _askBring(int haggles) async {
    final bring = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (c) => AlertDialog(
        backgroundColor: Palette.cream,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Text(
          'New account',
          style: TextStyle(fontWeight: FontWeight.w700, color: Palette.ink),
        ),
        content: Text(
          'This account has no progress yet. This phone has $haggles haggle${haggles == 1 ? '' : 's'} of yours.\n\n'
          'Start fresh, or bring this phone\'s progress into the account? Either way, this phone\'s progress comes '
          'back when you log out.',
          style: const TextStyle(height: 1.4),
        ),
        actions: [
          TextButton(
            key: const ValueKey('bring_fresh'),
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Start fresh'),
          ),
          TextButton(
            key: const ValueKey('bring_yes'),
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Bring my progress'),
          ),
        ],
      ),
    );
    return bring == true;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: Palette.cream,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      title: const Text(
        '🔑 Market account',
        style: TextStyle(fontWeight: FontWeight.w700, color: Palette.ink),
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              key: const ValueKey('acc_server'),
              controller: _server,
              keyboardType: TextInputType.url,
              autocorrect: false,
              decoration: _box('Market server address'),
            ),
            const SizedBox(height: 10),
            TextField(
              key: const ValueKey('acc_user'),
              controller: _user,
              autocorrect: false,
              maxLength: 20,
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9_.-]'))],
              decoration: _box('Username'),
            ),
            const SizedBox(height: 4),
            TextField(
              key: const ValueKey('acc_pw'),
              controller: _pw,
              obscureText: !_show,
              autocorrect: false,
              enableSuggestions: false,
              decoration: _box(
                'Password',
                suffix: IconButton(
                  icon: Icon(_show ? Icons.visibility_off_rounded : Icons.visibility_rounded),
                  onPressed: () => setState(() => _show = !_show),
                ),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(
                _error!,
                key: const ValueKey('acc_error'),
                style: const TextStyle(color: Palette.red, fontWeight: FontWeight.w600),
              ),
            ],
            const SizedBox(height: 8),
            const Text(
              'New here? Pick a username and a password (8+ characters), tap Sign up, and wait for the admin.',
              style: TextStyle(color: Palette.soft, fontSize: 12, height: 1.3),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: _busy ? null : () => Navigator.of(context).pop(), child: const Text('Cancel')),
        TextButton(
          key: const ValueKey('acc_signup'),
          onPressed: _busy ? null : () => _go(signUp: true),
          child: const Text('Sign up'),
        ),
        FilledButton(
          key: const ValueKey('acc_login'),
          style: FilledButton.styleFrom(backgroundColor: Palette.teal),
          onPressed: _busy ? null : () => _go(signUp: false),
          child: Text(_busy ? '…' : 'Log in'),
        ),
      ],
    );
  }
}

class PasswordDialog extends StatefulWidget {
  const PasswordDialog({super.key, required this.api});
  final Api api;
  @override
  State<PasswordDialog> createState() => _PasswordDialogState();
}

class _PasswordDialogState extends State<PasswordDialog> {
  final _old = TextEditingController();
  final _new = TextEditingController();
  final _again = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _old.dispose();
    _new.dispose();
    _again.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_new.text != _again.text) {
      setState(() => _error = "The new passwords don't match.");
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.api.changePassword(_old.text, _new.text);
      if (mounted) Navigator.of(context).pop(true);
    } on AccountError catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = e.message;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    Widget field(Key key, TextEditingController c, String label) => Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(key: key, controller: c, obscureText: true, autocorrect: false, decoration: _box(label)),
    );
    return AlertDialog(
      backgroundColor: Palette.cream,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      title: const Text(
        '🔒 Change password',
        style: TextStyle(fontWeight: FontWeight.w700, color: Palette.ink),
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            field(const ValueKey('pw_old'), _old, 'Current password'),
            field(const ValueKey('pw_new'), _new, 'New password (8+ characters)'),
            field(const ValueKey('pw_again'), _again, 'New password again'),
            if (_error != null)
              Text(
                _error!,
                key: const ValueKey('pw_error'),
                style: const TextStyle(color: Palette.red, fontWeight: FontWeight.w600),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: _busy ? null : () => Navigator.of(context).pop(false), child: const Text('Cancel')),
        FilledButton(
          key: const ValueKey('pw_save'),
          style: FilledButton.styleFrom(backgroundColor: Palette.teal),
          onPressed: _busy ? null : _save,
          child: const Text('Save'),
        ),
      ],
    );
  }
}

/// 👑 The admin's list: approve, reject, remove, or give someone a new password.
class PlayersScreen extends StatefulWidget {
  const PlayersScreen({super.key, required this.api});
  final Api api;
  @override
  State<PlayersScreen> createState() => _PlayersScreenState();
}

class _PlayersScreenState extends State<PlayersScreen> {
  List<Map> _players = [];
  int _aiToday = 0;
  bool _defaultPw = false;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _toast(String m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  Future<void> _load() async {
    try {
      final r = await widget.api.players();
      if (!mounted) return;
      setState(() {
        _players = (r['players'] as List).cast<Map>();
        _aiToday = (r['ai_today'] as num?)?.toInt() ?? 0;
        _defaultPw = r['default_password'] == true;
        _error = null;
        _loading = false;
      });
    } on AccountError catch (e) {
      if (mounted) {
        setState(() {
          _error = e.message;
          _loading = false;
        });
      }
    }
  }

  Future<void> _do(Map p, String action) async {
    try {
      final r = await widget.api.decide(p['id'] as int, action);
      if (!mounted) return;
      if (action == 'reset') {
        await showDialog<void>(
          context: context,
          builder: (c) => AlertDialog(
            title: Text('New password for ${p['username']}'),
            content: SelectableText(
              '${r['password']}',
              key: const ValueKey('reset_pw'),
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.pop(c);
                  Clipboard.setData(ClipboardData(text: '${r['password']}'));
                  _toast('Copied. Send it to ${p['username']} privately.');
                },
                child: const Text('Copy'),
              ),
            ],
          ),
        );
      } else {
        _toast('${p['username']}: ${statusText('${r['status']}')}');
      }
      await _load();
    } on AccountError catch (e) {
      if (mounted) _toast(e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final waiting = _players.where((p) => p['status'] == 'pending').length;
    return Scaffold(
      appBar: AppBar(title: const Text('👑 Players'), backgroundColor: Palette.cream),
      backgroundColor: Palette.cream,
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (_defaultPw)
              Container(
                key: const ValueKey('default_pw_warning'),
                padding: const EdgeInsets.all(12),
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(color: Palette.gold, borderRadius: BorderRadius.circular(16)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '⚠️ You\'re still using the default password "admin". Change it so nobody else can approve '
                      'players.',
                      style: TextStyle(fontWeight: FontWeight.w600, height: 1.3),
                    ),
                    const SizedBox(height: 8),
                    Bouncy(
                      onTap: () async {
                        final ok = await showDialog<bool>(
                          context: context,
                          builder: (_) => PasswordDialog(api: widget.api),
                        );
                        if (ok == true) await _load();
                      },
                      child: const Pill(text: 'Change password', icon: '🔒'),
                    ),
                  ],
                ),
              ),
            if (_loading)
              const Center(
                child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator()),
              ),
            if (_error != null) Text(_error!, style: const TextStyle(color: Palette.red)),
            if (!_loading && _error == null)
              Text(
                '$waiting waiting · ${_players.length} in all · $_aiToday AI chats today',
                style: const TextStyle(color: Palette.soft),
              ),
            if (!_loading && _error == null && _players.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 24),
                child: Text('No sign-ups yet. Share the market address with friends!', textAlign: TextAlign.center),
              ),
            for (final p in _players)
              Card(
                color: Colors.white,
                margin: const EdgeInsets.only(top: 10),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              '${p['username']}',
                              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                            ),
                          ),
                          PopupMenuButton<String>(
                            key: ValueKey('more_${p['username']}'),
                            onSelected: (a) => _do(p, a),
                            itemBuilder: (_) => const [
                              PopupMenuItem(value: 'reset', child: Text('Give a new password')),
                            ],
                          ),
                        ],
                      ),
                      Text(statusText('${p['status']}'), style: const TextStyle(color: Palette.soft)),
                      Text(
                        'Joined ${'${p['created_at']}'.split('T').first} · ${p['ai_today']} AI chats today',
                        style: const TextStyle(color: Palette.soft, fontSize: 12),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          if (p['status'] != 'approved')
                            Bouncy(
                              key: ValueKey('approve_${p['username']}'),
                              onTap: () => _do(p, 'approve'),
                              child: const Pill(text: 'Approve', icon: '✅', color: Palette.green),
                            ),
                          if (p['status'] == 'pending')
                            Bouncy(
                              key: ValueKey('reject_${p['username']}'),
                              onTap: () => _do(p, 'reject'),
                              child: const Pill(text: 'Reject', icon: '❌'),
                            ),
                          if (p['status'] == 'approved')
                            Bouncy(
                              key: ValueKey('remove_${p['username']}'),
                              onTap: () => _do(p, 'remove'),
                              child: const Pill(text: 'Remove', icon: '🚫'),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
