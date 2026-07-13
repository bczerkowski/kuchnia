import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:uuid/uuid.dart';

import '../models/recipe.dart';

/// Domyślne kategorie — można dodać własne przy zapisie przepisu.
const List<String> kDefaultCategories = [
  'Śniadanie',
  'Obiad',
  'Kolacja',
  'Podwieczorek',
  'Deser',
  'Napoje',
];

/// Centralny magazyn przepisów. Trzyma dane w Hive (IndexedDB w przeglądarce),
/// więc wszystko zostaje na urządzeniu i działa offline.
///
/// Boxy mają własny prefiks `kuchnia_`, żeby NIE kolidowały z innymi apkami na
/// tym samym adresie (wcześniej współdzielony box `meta` mieszał sesje sync).
class RecipeStore extends ChangeNotifier {
  static const _recipesBox = 'kuchnia_recipes';
  static const _settingsBox = 'kuchnia_settings';
  static const _metaBox = 'kuchnia_meta';
  static const _backupsBox = 'kuchnia_backups';
  static const _catKey = 'categories';

  // Ile lokalnych kopii awaryjnych trzymamy.
  static const _maxBackups = 8;

  final _uuid = const Uuid();
  late Box _recipes;
  late Box _settings;
  late Box _meta;
  late Box _backups;

  Future<void> init() async {
    await Hive.initFlutter();
    _recipes = await Hive.openBox(_recipesBox);
    _settings = await Hive.openBox(_settingsBox);
    _meta = await Hive.openBox(_metaBox);
    _backups = await Hive.openBox(_backupsBox);

    // Jednorazowa migracja ze starych, współdzielonych nazw (nic nie gubimy —
    // stare boxy zostają nietknięte jako zapas).
    await _migrate('recipes', _recipes);
    await _migrate('settings', _settings);
    await _migrate('meta', _meta);

    if (_settings.get(_catKey) == null) {
      await _settings.put(_catKey, List<String>.from(kDefaultCategories));
    }
  }

  Future<void> _migrate(String oldName, Box target) async {
    if (target.isNotEmpty) return; // już zmigrowane / ma dane
    final old = await Hive.openBox(oldName);
    if (old.isNotEmpty) {
      for (final k in old.keys) {
        await target.put(k, old.get(k));
      }
    }
  }

  int get count => _recipes.length;

  // ---- Trwałe klucz–wartość (dla sync: sesja, znaczniki) ----
  String? metaGetString(String key) => _meta.get(key) as String?;
  bool? metaGetBool(String key) => _meta.get(key) as bool?;
  int? metaGetInt(String key) => _meta.get(key) as int?;
  Future<void> metaSet(String key, Object? value) async =>
      value == null ? _meta.delete(key) : _meta.put(key, value);
  Future<void> metaRemove(String key) async => _meta.delete(key);

  // ---- Kategorie ----
  List<String> get categories => List<String>.from(
      _settings.get(_catKey, defaultValue: kDefaultCategories) as List);

  Future<void> addCategory(String name) async {
    final n = name.trim();
    if (n.isEmpty) return;
    final cats = categories;
    if (cats.any((c) => c.toLowerCase() == n.toLowerCase())) return;
    cats.add(n);
    await _settings.put(_catKey, cats);
    notifyListeners();
  }

  // ---- Przepisy ----
  List<Recipe> get all {
    final list = _recipes.values
        .map((e) => Recipe.fromMap(Map<String, dynamic>.from(e as Map)))
        .toList();
    list.sort((a, b) {
      // Ulubione na górze, potem najnowsze.
      if (a.favorite != b.favorite) return a.favorite ? -1 : 1;
      return b.createdAt.compareTo(a.createdAt);
    });
    return list;
  }

  int countIn(String category) =>
      all.where((r) => r.category == category).length;

  Recipe? byId(String id) {
    final raw = _recipes.get(id);
    if (raw == null) return null;
    return Recipe.fromMap(Map<String, dynamic>.from(raw as Map));
  }

  String newId() => _uuid.v4();

  Future<void> save(Recipe r) async {
    await _recipes.put(r.id, r.toMap());
    await _snapshot(); // kopia dobrego stanu po każdej zmianie
    notifyListeners();
  }

  Future<void> delete(String id) async {
    await _snapshot(); // najpierw zapisz stan sprzed usunięcia (można cofnąć)
    await _recipes.delete(id);
    notifyListeners();
  }

  Future<void> toggleFavorite(Recipe r) async {
    r.favorite = !r.favorite;
    await save(r);
  }

  // ---- Kopia zapasowa (eksport / import) ----
  Map<String, dynamic> exportData() => {
        'app': 'moja-kuchnia',
        'version': 1,
        'exportedAt': DateTime.now().toIso8601String(),
        'categories': categories,
        'recipes': all.map((r) => r.toMap()).toList(),
      };

  /// Pełne zastąpienie zawartości danymi z chmury (sync). Lokalne przepisy
  /// są nadpisywane dokładnie tym, co przyszło (łącznie z usunięciami).
  Future<void> replaceFromMap(Map data) async {
    // KLUCZOWE: zanim cokolwiek nadpiszemy, zapisz stan lokalny do kopii
    // awaryjnej — dzięki temu żadne pobranie z chmury nie może bezpowrotnie
    // skasować lokalnych przepisów.
    await _snapshot();
    await _recipes.clear();
    final recs = data['recipes'];
    if (recs is List) {
      for (final m in recs) {
        if (m is Map && m['id'] is String) {
          final r = Recipe.fromMap(Map<String, dynamic>.from(m));
          await _recipes.put(r.id, r.toMap());
        }
      }
    }
    final cats = data['categories'];
    if (cats is List) {
      final list = cats.whereType<String>().toList();
      if (list.isNotEmpty) await _settings.put(_catKey, list);
    }
    notifyListeners();
  }

  /// Wczytuje przepisy z kopii. Przepisy o tym samym id nadpisują istniejące,
  /// nowe są dopisywane. Zwraca liczbę wczytanych przepisów.
  Future<int> importData(Map data) async {
    await _snapshot();
    final cats = data['categories'];
    if (cats is List) {
      for (final c in cats) {
        if (c is String) await addCategory(c);
      }
    }
    var n = 0;
    final recs = data['recipes'];
    if (recs is List) {
      for (final m in recs) {
        if (m is Map && m['id'] is String) {
          final recipe = Recipe.fromMap(Map<String, dynamic>.from(m));
          await _recipes.put(recipe.id, recipe.toMap());
          n++;
        }
      }
    }
    notifyListeners();
    return n;
  }

  // ---- Lokalne kopie awaryjne (undo/przywracanie) ------------------------

  /// Zapisuje bieżący stan jako kopię awaryjną (pomija, gdy pusto lub gdy
  /// identyczne z ostatnią). Trzyma maks. [_maxBackups] najnowszych.
  Future<void> _snapshot() async {
    if (_recipes.isEmpty) return; // nie ma czego chronić
    final json = jsonEncode(exportData());
    final keys = _backupKeys();
    if (keys.isNotEmpty && _backups.get(keys.last.toString()) == json) {
      return; // bez duplikatu
    }
    await _backups.put(DateTime.now().millisecondsSinceEpoch.toString(), json);
    final all = _backupKeys();
    while (all.length > _maxBackups) {
      await _backups.delete(all.removeAt(0).toString());
    }
  }

  List<int> _backupKeys() {
    final keys =
        _backups.keys.map((e) => int.tryParse(e.toString()) ?? 0).toList();
    keys.sort();
    return keys;
  }

  /// Lista kopii awaryjnych (najnowsze pierwsze): kiedy i ile przepisów.
  List<({int ts, int count})> backups() {
    final out = <({int ts, int count})>[];
    for (final k in _backupKeys()) {
      final json = _backups.get(k.toString());
      if (json is! String) continue;
      out.add((ts: k, count: _recipeCountOf(json)));
    }
    out.sort((a, b) => b.ts.compareTo(a.ts));
    return out;
  }

  /// Przywraca stan z kopii awaryjnej (bieżący i tak trafia najpierw do kopii).
  Future<void> restoreBackup(int ts) async {
    final json = _backups.get(ts.toString());
    if (json is String) {
      await replaceFromMap(jsonDecode(json) as Map);
    }
  }

  static int _recipeCountOf(String json) {
    try {
      final m = jsonDecode(json);
      final r = (m is Map) ? m['recipes'] : null;
      return r is List ? r.length : 0;
    } catch (_) {
      return 0;
    }
  }
}
