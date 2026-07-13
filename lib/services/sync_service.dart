import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../data/store.dart';
import 'supabase_config.dart';

enum SyncState { offline, syncing, synced, error }

/// Synchronizacja w chmurze po zwykłym HTTP (bez wtyczek Fluttera, więc nic nie
/// uruchamia się przy starcie aplikacji — funkcja jest bezczynna, dopóki
/// użytkownik się nie zaloguje).
///
/// Cały zbiór (przepisy + kategorie) jest przechowywany jako jeden dokument
/// JSON na użytkownika w tabeli Supabase `recipes`. Zmiany są wypychane
/// (z opóźnieniem) i pobierane (co ~15 s oraz na żądanie), rozstrzygane
/// „ostatni wygrywa" po `updated_at`.
class SyncService extends ChangeNotifier {
  static final Uri _base = Uri.parse(SupabaseConfig.url);

  RecipeStore? _store;
  RecipeStore get store => _store!;

  // Sesja (trwała w boxie Hive `meta`; bez wtyczek, bez sieci przy starcie).
  String? _access, _refresh, _uid, _email;
  DateTime? _expiresAt;

  SyncState _state = SyncState.offline;
  String? _message;
  DateTime? _lastSyncedAt;
  String? _lastSyncedData; // ochrona przed echem
  bool _applyingRemote = false;
  Timer? _pushDebounce;
  Timer? _poll;
  bool _started = false;
  bool _listening = false;

  /// Rozstrzygnięcie pierwszego logowania (to urządzenie ma przepisy ORAZ
  /// chmura już coś ma): true = zostaw chmurę, false = wyślij to urządzenie.
  Future<bool> Function(int localRecipes)? conflictResolver;

  SyncState get state => _state;
  String? get message => _message;
  DateTime? get lastSyncedAt => _lastSyncedAt;
  bool get signedIn => _refresh != null && _uid != null;
  String? get email => _email;

  void _set(SyncState s, [String? m]) {
    _state = s;
    _message = m;
    notifyListeners();
  }

  /// Wywoływane raz po runApp. Odtwarza zapisaną sesję (tylko z Hive, bez sieci)
  /// i startuje synchronizację w tle, jeśli użytkownik jest zalogowany.
  Future<void> init(RecipeStore store) async {
    _store = store;
    _access = store.metaGetString('sb_access');
    _refresh = store.metaGetString('sb_refresh');
    _uid = store.metaGetString('sb_uid');
    _email = store.metaGetString('sb_email');
    final e = store.metaGetInt('sb_exp');
    _expiresAt = e == null ? null : DateTime.fromMillisecondsSinceEpoch(e);
    if (signedIn) await _start();
  }

  // --- Auth ---------------------------------------------------------------
  Future<void> signUp(String email, String password) async {
    final data = await _postJson('/auth/v1/signup',
        {'email': email.trim(), 'password': password});
    await _saveSession(data);
    if (!signedIn) {
      throw 'Konto utworzone — jeśli włączone jest potwierdzanie e-mail, '
          'potwierdź je, a potem zaloguj się.';
    }
    await _afterAuth();
  }

  Future<void> signIn(String email, String password) async {
    final data = await _postJson('/auth/v1/token?grant_type=password',
        {'email': email.trim(), 'password': password});
    await _saveSession(data);
    await _afterAuth();
  }

  Future<void> signOut() async {
    _stop();
    for (final k in ['sb_access', 'sb_refresh', 'sb_uid', 'sb_email', 'sb_exp']) {
      await store.metaRemove(k);
    }
    _access = _refresh = _uid = _email = null;
    _expiresAt = null;
    notifyListeners();
  }

  Future<void> _saveSession(Map<String, dynamic> m) async {
    _access = m['access_token'] as String?;
    _refresh = (m['refresh_token'] as String?) ?? _refresh;
    final user = m['user'] as Map?;
    _uid = (user?['id'] ?? m['id'] ?? _uid) as String?;
    _email = (user?['email'] as String?) ?? _email;
    final expIn = m['expires_in'];
    _expiresAt =
        expIn is int ? DateTime.now().add(Duration(seconds: expIn)) : null;
    if (_access != null) await store.metaSet('sb_access', _access);
    if (_refresh != null) await store.metaSet('sb_refresh', _refresh);
    if (_uid != null) await store.metaSet('sb_uid', _uid);
    if (_email != null) await store.metaSet('sb_email', _email);
    if (_expiresAt != null) {
      await store.metaSet('sb_exp', _expiresAt!.millisecondsSinceEpoch);
    }
  }

  Future<void> _afterAuth() async {
    notifyListeners();
    await _start(interactive: true);
  }

  Future<void> _ensureToken() async {
    if (_refresh == null) throw 'Nie zalogowano';
    if (_expiresAt != null &&
        DateTime.now()
            .isBefore(_expiresAt!.subtract(const Duration(seconds: 60)))) {
      return;
    }
    final data = await _postJson('/auth/v1/token?grant_type=refresh_token',
        {'refresh_token': _refresh});
    await _saveSession(data);
  }

  // --- Cykl życia ---------------------------------------------------------
  Future<void> _start({bool interactive = false}) async {
    if (_started) return;
    _started = true;
    _set(SyncState.syncing, 'Synchronizuję…');
    try {
      await _reconcile(interactive: interactive);
      conflictResolver = null;
      _listenLocal();
      _startPolling();
      _set(SyncState.synced);
    } catch (e) {
      _set(SyncState.error, _friendly(e));
    }
  }

  void _stop() {
    _started = false;
    _pushDebounce?.cancel();
    _poll?.cancel();
    if (_listening) {
      store.removeListener(_onLocalChange);
      _listening = false;
    }
    _lastSyncedData = null;
    _lastSyncedAt = null;
    _set(SyncState.offline);
  }

  // --- Odczyt/zapis w chmurze --------------------------------------------
  Future<({String? data, DateTime? updatedAt})> _fetchCloud() async {
    await _ensureToken();
    final list = await _getJson(
        '/rest/v1/${SupabaseConfig.table}?select=data,updated_at');
    if (list is! List || list.isEmpty) return (data: null, updatedAt: null);
    final row = list.first as Map;
    return (
      data: row['data'] as String?,
      updatedAt: DateTime.parse(row['updated_at'] as String).toUtc()
    );
  }

  /// Tania kontrola: tylko znacznik czasu, nigdy całego (potencjalnie
  /// wielomegabajtowego, ze zdjęciami) dokumentu. Pełny zbiór pobieramy dopiero,
  /// gdy to pokaże, że chmura jest nowsza — inaczej co 15 s pobieralibyśmy
  /// wszystkie zdjęcia od nowa (ogromny transfer / egress).
  Future<DateTime?> _fetchCloudMeta() async {
    await _ensureToken();
    final list =
        await _getJson('/rest/v1/${SupabaseConfig.table}?select=updated_at');
    if (list is! List || list.isEmpty) return null;
    return DateTime.parse((list.first as Map)['updated_at'] as String).toUtc();
  }

  Future<void> _reconcile({required bool interactive}) async {
    final localCount = store.count;
    final cloud = await _fetchCloud();
    if (cloud.data == null) {
      await _push(force: true); // zasiej chmurę z tego urządzenia
      return;
    }
    final last = _readLastAt();
    final dirty = _readDirty();
    final cloudIsNew = last == null || cloud.updatedAt!.isAfter(last);

    if (interactive &&
        last == null &&
        localCount > 0 &&
        conflictResolver != null) {
      final keepCloud = await conflictResolver!(localCount);
      if (keepCloud) {
        await _applyRemote(cloud.data!, cloud.updatedAt!, force: true);
      } else {
        await _push(force: true);
      }
      return;
    }

    if (cloudIsNew) {
      await _applyRemote(cloud.data!, cloud.updatedAt!);
    } else if (dirty) {
      await _push(force: true);
    }
  }

  Future<void> _push({bool force = false}) async {
    final json = jsonEncode(store.exportData());
    if (!force && json == _lastSyncedData) {
      _set(SyncState.synced);
      return;
    }
    await _ensureToken();
    final now = DateTime.now().toUtc();
    await _postJson(
      '/rest/v1/${SupabaseConfig.table}',
      {'user_id': _uid, 'data': json, 'updated_at': now.toIso8601String()},
      rest: true,
      prefer: 'resolution=merge-duplicates',
    );
    _lastSyncedData = json;
    _lastSyncedAt = now;
    await _writeLastAt(now);
    await _writeDirty(false);
    _set(SyncState.synced);
  }

  Future<void> _applyRemote(String data, DateTime updatedAt,
      {bool force = false}) async {
    if (data == _lastSyncedData) {
      _lastSyncedAt = updatedAt;
      await _writeLastAt(updatedAt);
      return;
    }
    // STRAŻNIK BEZPIECZEŃSTWA: nigdy nie pozwól, żeby wyraźnie mniejsza wersja
    // z chmury po cichu skasowała większą lokalną (tak można stracić przepisy
    // albo zdjęcia). Jeśli pobranie zabrałoby sporą część danych — zostaw
    // lokalne i to je wypchnij jako źródło prawdy. Świadome akcje (pierwsze
    // logowanie „użyj chmury") omijają strażnika przez force:true.
    if (!force) {
      final localCount = store.count;
      final remoteCount = _recipeCount(data);
      final lost = localCount - remoteCount;
      final localImages = _localImageCount;
      final remoteImages = _imageCount(data);
      final lostImages = localImages - remoteImages;
      final destructive = (remoteCount >= 0 &&
              localCount > 0 &&
              lost >= 2 &&
              remoteCount < localCount * 0.75) ||
          (remoteImages >= 0 &&
              localImages > 0 &&
              lostImages >= 2 &&
              remoteImages < localImages * 0.75);
      if (destructive) {
        await _writeDirty(true);
        await _push(force: true);
        _set(SyncState.synced,
            'Zachowano dane z tego urządzenia ($localCount przepisów, '
            '$localImages zdjęć) — chmura miała mniej.');
        return;
      }
    }
    _applyingRemote = true;
    try {
      await store.replaceFromMap(jsonDecode(data) as Map);
      _lastSyncedData = data;
      _lastSyncedAt = updatedAt;
      await _writeLastAt(updatedAt);
      await _writeDirty(false);
    } finally {
      _applyingRemote = false;
    }
  }

  int get _localImageCount {
    var n = 0;
    for (final r in store.all) {
      n += r.images.length;
    }
    return n;
  }

  int _recipeCount(String data) {
    try {
      final m = jsonDecode(data);
      final r = (m is Map) ? m['recipes'] : null;
      return r is List ? r.length : -1;
    } catch (_) {
      return -1;
    }
  }

  int _imageCount(String data) {
    try {
      final m = jsonDecode(data);
      final r = (m is Map) ? m['recipes'] : null;
      if (r is! List) return -1;
      var n = 0;
      for (final e in r) {
        if (e is Map) {
          final imgs = e['images'];
          if (imgs is List) {
            n += imgs.length;
          } else if (e['imageBase64'] is String &&
              (e['imageBase64'] as String).isNotEmpty) {
            n += 1;
          }
        }
      }
      return n;
    } catch (_) {
      return -1;
    }
  }

  /// Ręczne „Synchronizuj teraz" — wymuś pobranie najnowszej wersji z chmury.
  Future<void> pullNow() async {
    if (!signedIn) return;
    _set(SyncState.syncing, 'Sprawdzam…');
    try {
      final c = await _fetchCloud();
      if (c.data != null) await _applyRemote(c.data!, c.updatedAt!);
      _set(SyncState.synced);
    } catch (e) {
      _set(SyncState.error, _friendly(e));
    }
  }

  /// Ręczne „Wyślij to urządzenie do chmury" — nadpisuje chmurę stanem lokalnym
  /// (przydatne, gdy w chmurze jest starsza wersja, np. bez zdjęć).
  Future<void> pushNow() async {
    if (!signedIn) return;
    _set(SyncState.syncing, 'Wysyłam…');
    try {
      await _push(force: true);
      _set(SyncState.synced);
    } catch (e) {
      _set(SyncState.error, _friendly(e));
    }
  }

  // --- Nasłuch zmian ------------------------------------------------------
  void _listenLocal() {
    if (_listening) return;
    store.addListener(_onLocalChange);
    _listening = true;
  }

  void _onLocalChange() {
    if (_applyingRemote) return;
    _writeDirty(true);
    _set(SyncState.syncing);
    _pushDebounce?.cancel();
    _pushDebounce = Timer(const Duration(seconds: 2), () async {
      try {
        await _push();
      } catch (e) {
        _set(SyncState.error, _friendly(e));
      }
    });
  }

  void _startPolling() {
    _poll?.cancel();
    _poll = Timer.periodic(const Duration(seconds: 15), (_) async {
      if (_applyingRemote || _state == SyncState.syncing) return;
      try {
        // Najpierw tania kontrola daty; pełne dane pobierz tylko, gdy chmura
        // faktycznie się zmieniła.
        final at = await _fetchCloudMeta();
        if (at != null &&
            (_lastSyncedAt == null || at.isAfter(_lastSyncedAt!))) {
          final c = await _fetchCloud();
          if (c.data != null) {
            await _applyRemote(c.data!, c.updatedAt!);
            _set(SyncState.synced);
          }
        }
      } catch (_) {/* przejściowy problem sieci — zostaw stan */}
    });
  }

  // --- HTTP ---------------------------------------------------------------
  Map<String, String> get _restHeaders => {
        'apikey': SupabaseConfig.anonKey,
        'Authorization': 'Bearer $_access',
        'Content-Type': 'application/json',
      };

  Future<Map<String, dynamic>> _postJson(String path, Object body,
      {bool rest = false, String? prefer}) async {
    final headers = rest
        ? {..._restHeaders, 'Prefer': ?prefer}
        : {
            'apikey': SupabaseConfig.anonKey,
            'Content-Type': 'application/json',
          };
    final res = await http
        .post(_base.resolve(path), headers: headers, body: jsonEncode(body))
        .timeout(const Duration(seconds: 30));
    _ensureOk(res);
    if (res.body.isEmpty) return {};
    final decoded = jsonDecode(res.body);
    return decoded is Map<String, dynamic> ? decoded : {'data': decoded};
  }

  Future<dynamic> _getJson(String path) async {
    final res = await http
        .get(_base.resolve(path), headers: _restHeaders)
        .timeout(const Duration(seconds: 30));
    _ensureOk(res);
    return res.body.isEmpty ? null : jsonDecode(res.body);
  }

  void _ensureOk(http.Response res) {
    if (res.statusCode >= 200 && res.statusCode < 300) return;
    String msg = 'Błąd sieci (${res.statusCode})';
    try {
      final d = jsonDecode(res.body);
      if (d is Map) {
        msg = (d['error_description'] ??
                d['msg'] ??
                d['message'] ??
                d['error'] ??
                msg)
            .toString();
      }
    } catch (_) {/* zostaw domyślny komunikat */}
    throw msg;
  }

  // --- Znaczniki (per konto) ----------------------------------------------
  DateTime? _readLastAt() {
    final s = store.metaGetString('sync_last_$_uid');
    return s == null ? null : DateTime.tryParse(s);
  }

  Future<void> _writeLastAt(DateTime at) =>
      store.metaSet('sync_last_$_uid', at.toIso8601String());

  bool _readDirty() => store.metaGetBool('sync_dirty_$_uid') ?? false;

  Future<void> _writeDirty(bool v) => store.metaSet('sync_dirty_$_uid', v);

  String _friendly(Object e) => e is String ? e : e.toString();

  @override
  void dispose() {
    _stop();
    super.dispose();
  }
}

/// Singleton używany w całej aplikacji.
final sync = SyncService();
