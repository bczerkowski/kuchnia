import 'package:flutter/material.dart';

import '../data/backup.dart';
import '../data/store.dart';
import '../services/sync_service.dart';
import '../theme.dart';

/// Synchronizacja w chmurze (logowanie/rejestracja, status) + kopia JSON.
class SyncScreen extends StatefulWidget {
  final RecipeStore store;
  const SyncScreen({super.key, required this.store});

  @override
  State<SyncScreen> createState() => _SyncScreenState();
}

class _SyncScreenState extends State<SyncScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  String? _error;

  RecipeStore get store => widget.store;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<bool> _askConflict(int localRecipes) async {
    if (!mounted) return true;
    final keep = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Znaleziono dwa zbiory'),
        content: Text(
            'To urządzenie ma $localRecipes ${_przepisow(localRecipes)}, a Twoje '
            'konto ma już zapisany zbiór w chmurze.\n\nKtóry zostawić? '
            'Drugi zostanie zastąpiony.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Wyślij TO urządzenie'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.terracotta),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Użyj chmury'),
          ),
        ],
      ),
    );
    return keep ?? true;
  }

  String _przepisow(int n) {
    if (n == 1) return 'przepis';
    final mod10 = n % 10, mod100 = n % 100;
    if (mod10 >= 2 && mod10 <= 4 && (mod100 < 12 || mod100 > 14)) {
      return 'przepisy';
    }
    return 'przepisów';
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    sync.conflictResolver = _askConflict;
    try {
      await action();
    } catch (e) {
      _error = e is String
          ? e
          : 'Nie udało się zalogować. Sprawdź e-mail/hasło i spróbuj ponownie.';
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _signIn() => sync.signIn(_email.text, _password.text);

  Future<void> _signUp() async {
    if (_password.text.length < 6) {
      throw 'Hasło musi mieć co najmniej 6 znaków.';
    }
    await sync.signUp(_email.text, _password.text);
  }

  void _toast(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  Future<void> _exportBackup() async {
    if (store.all.isEmpty) {
      _toast('Brak przepisów do zapisania.');
      return;
    }
    exportToFile(store);
    _toast('Zapisuję plik z przepisami…');
  }

  Future<void> _importBackup() async {
    final n = await importFromFile(store);
    if (!mounted) return;
    _toast(n == null ? 'Nie wczytano pliku.' : 'Wczytano $n ${_przepisow(n)}. 🎉');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Synchronizacja')),
      body: AnimatedBuilder(
        animation: sync,
        builder: (context, _) {
          return SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 460),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    sync.signedIn ? _signedIn() : _signedOut(),
                    const SizedBox(height: 28),
                    _backupSection(),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _signedOut() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Synchronizuj przepisy między urządzeniami',
            style: AppTheme.heading(22)),
        const SizedBox(height: 6),
        const Text(
          'Zaloguj się (lub załóż konto), aby mieć te same przepisy na '
          'komputerze i telefonie. Zmiany synchronizują się automatycznie.',
          style: TextStyle(color: AppColors.muted, height: 1.4),
        ),
        const SizedBox(height: 20),
        TextField(
          controller: _email,
          keyboardType: TextInputType.emailAddress,
          autocorrect: false,
          enabled: !_busy,
          decoration: const InputDecoration(labelText: 'E-mail'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _password,
          obscureText: true,
          enabled: !_busy,
          decoration: const InputDecoration(labelText: 'Hasło'),
        ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFFBEAE7),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                const Icon(Icons.error_outline,
                    color: Color(0xFFB3261E), size: 18),
                const SizedBox(width: 8),
                Expanded(
                    child: Text(_error!,
                        style: const TextStyle(
                            color: Color(0xFFB3261E), fontSize: 13.5))),
              ],
            ),
          ),
        ],
        const SizedBox(height: 18),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.terracotta,
            minimumSize: const Size.fromHeight(50),
          ),
          onPressed: _busy ? null : () => _run(_signIn),
          child: _busy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white))
              : const Text('Zaloguj się',
                  style: TextStyle(fontWeight: FontWeight.w700)),
        ),
        const SizedBox(height: 10),
        OutlinedButton(
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(50),
            side: const BorderSide(color: AppColors.line),
            foregroundColor: AppColors.brown,
          ),
          onPressed: _busy ? null : () => _run(_signUp),
          child: const Text('Załóż nowe konto'),
        ),
        const SizedBox(height: 14),
        const Text(
          'Użyj dowolnego e-maila i wybranego hasła. Twój zbiór jest prywatny. '
          'Możesz użyć tego samego konta co w innych aplikacjach.',
          style: TextStyle(color: AppColors.muted, fontSize: 12.5, height: 1.4),
        ),
      ],
    );
  }

  Widget _signedIn() {
    final (icon, label, color) = _statusBits();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.cloud_done_outlined, color: AppColors.olive),
            const SizedBox(width: 10),
            Expanded(
              child: Text(sync.email ?? 'Zalogowano',
                  style: AppTheme.heading(19)),
            ),
          ],
        ),
        const SizedBox(height: 18),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.line),
          ),
          child: Row(
            children: [
              Icon(icon, color: color, size: 22),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label,
                        style: const TextStyle(
                            fontSize: 15.5, fontWeight: FontWeight.w700)),
                    if (sync.lastSyncedAt != null)
                      Text('Ostatnio: ${_ago(sync.lastSyncedAt!)}',
                          style: const TextStyle(
                              color: AppColors.muted, fontSize: 12.5)),
                    if (sync.message != null && sync.state == SyncState.error)
                      Text(sync.message!,
                          style: const TextStyle(
                              color: Color(0xFFB3261E), fontSize: 12.5)),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        const Text(
          'Przepisy synchronizują się automatycznie przy każdej zmianie. Edycje '
          'z jednego urządzenia pojawiają się na drugim w ~15 sekund (online).',
          style: TextStyle(color: AppColors.muted, height: 1.4, fontSize: 13.5),
        ),
        const SizedBox(height: 16),
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
            side: const BorderSide(color: AppColors.line),
            foregroundColor: AppColors.brown,
          ),
          onPressed: () => sync.pullNow(),
          icon: const Icon(Icons.refresh, size: 18),
          label: const Text('Synchronizuj teraz'),
        ),
        const SizedBox(height: 8),
        TextButton.icon(
          onPressed: () => sync.signOut(),
          icon: const Icon(Icons.logout, size: 18),
          style: TextButton.styleFrom(foregroundColor: const Color(0xFFB3261E)),
          label: const Text('Wyloguj się'),
        ),
      ],
    );
  }

  Widget _backupSection() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.download_outlined, color: AppColors.muted),
              const SizedBox(width: 10),
              Text('Kopia zapasowa (plik JSON)', style: AppTheme.heading(18)),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            'Niezależnie od chmury możesz pobrać wszystkie przepisy do pliku '
            'i wczytać go z powrotem (ręczny backup / przeniesienie).',
            style: TextStyle(color: AppColors.muted, fontSize: 13, height: 1.4),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: AppColors.line),
                    foregroundColor: AppColors.olive,
                  ),
                  onPressed: _exportBackup,
                  icon: const Icon(Icons.file_download_outlined, size: 18),
                  label: const Text('Eksportuj'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: AppColors.line),
                    foregroundColor: AppColors.olive,
                  ),
                  onPressed: _importBackup,
                  icon: const Icon(Icons.file_upload_outlined, size: 18),
                  label: const Text('Importuj'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  (IconData, String, Color) _statusBits() {
    switch (sync.state) {
      case SyncState.syncing:
        return (Icons.sync, 'Synchronizuję…', AppColors.honey);
      case SyncState.synced:
        return (Icons.check_circle_outline, 'Zsynchronizowano',
            const Color(0xFF2E7D32));
      case SyncState.error:
        return (Icons.error_outline, 'Problem z synchronizacją',
            const Color(0xFFB3261E));
      case SyncState.offline:
        return (Icons.cloud_off_outlined, 'Offline', AppColors.muted);
    }
  }

  String _ago(DateTime t) {
    final d = DateTime.now().difference(t);
    if (d.inSeconds < 60) return 'przed chwilą';
    if (d.inMinutes < 60) return '${d.inMinutes} min temu';
    if (d.inHours < 24) return '${d.inHours} godz. temu';
    return '${d.inDays} dni temu';
  }
}
