import 'package:flutter/material.dart';

import '../data/backup.dart';
import '../data/store.dart';
import '../models/recipe.dart';
import '../theme.dart';
import '../widgets/recipe_card.dart';
import 'recipe_detail_screen.dart';
import 'recipe_edit_screen.dart';

class HomeScreen extends StatefulWidget {
  final RecipeStore store;
  const HomeScreen({super.key, required this.store});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  static const _favFilter = '★ Ulubione';
  static const _allFilter = 'Wszystkie';

  String _filter = _allFilter;
  String _query = '';

  RecipeStore get store => widget.store;

  List<Recipe> get _visible {
    var list = store.all;
    if (_filter == _favFilter) {
      list = list.where((r) => r.favorite).toList();
    } else if (_filter != _allFilter) {
      list = list.where((r) => r.category == _filter).toList();
    }
    if (_query.trim().isNotEmpty) {
      final q = _query.toLowerCase();
      list = list
          .where((r) =>
              r.title.toLowerCase().contains(q) ||
              r.ingredients.toLowerCase().contains(q) ||
              r.steps.toLowerCase().contains(q))
          .toList();
    }
    return list;
  }

  Future<void> _openEditor({Recipe? recipe}) async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => RecipeEditScreen(store: store, existing: recipe),
    ));
    if (mounted) setState(() {});
  }

  Future<void> _openDetail(Recipe r) async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => RecipeDetailScreen(store: store, recipeId: r.id),
    ));
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openEditor(),
        icon: const Icon(Icons.add),
        label: const Text('Nowy przepis',
            style: TextStyle(fontWeight: FontWeight.w700)),
      ),
      body: SafeArea(
        child: AnimatedBuilder(
          animation: store,
          builder: (context, _) {
            final recipes = _visible;
            return CustomScrollView(
              slivers: [
                SliverToBoxAdapter(child: _header()),
                SliverToBoxAdapter(child: _searchBar()),
                SliverToBoxAdapter(child: _categoryChips()),
                if (recipes.isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: _emptyState(),
                  )
                else
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
                    sliver: SliverLayoutBuilder(
                      builder: (context, constraints) {
                        final w = constraints.crossAxisExtent;
                        final cols = w > 1100
                            ? 4
                            : w > 800
                                ? 3
                                : w > 520
                                    ? 2
                                    : 1;
                        return SliverGrid(
                          gridDelegate:
                              SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: cols,
                            mainAxisSpacing: 16,
                            crossAxisSpacing: 16,
                            childAspectRatio: 0.82,
                          ),
                          delegate: SliverChildBuilderDelegate(
                            (context, i) {
                              final r = recipes[i];
                              return RecipeCard(
                                recipe: r,
                                onTap: () => _openDetail(r),
                                onToggleFavorite: () =>
                                    store.toggleFavorite(r),
                              );
                            },
                            childCount: recipes.length,
                          ),
                        );
                      },
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _header() {
    final total = store.all.length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('🍳', style: TextStyle(fontSize: 30)),
              const SizedBox(width: 10),
              Expanded(child: Text('Moja Kuchnia', style: AppTheme.heading(34))),
              _backupMenu(),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            total == 0
                ? 'Zacznijmy zbierać Twoje ulubione przepisy.'
                : 'Masz tu $total ${_recipeWord(total)}. Smacznego!',
            style: const TextStyle(fontSize: 15, color: AppColors.muted),
          ),
        ],
      ),
    );
  }

  Widget _backupMenu() {
    return PopupMenuButton<String>(
      tooltip: 'Kopia zapasowa',
      icon: const Icon(Icons.more_vert, color: AppColors.brown),
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      onSelected: (value) async {
        if (value == 'export') {
          if (store.all.isEmpty) {
            _snack('Brak przepisów do zapisania.');
            return;
          }
          exportToFile(store);
          _snack('Zapisuję plik z przepisami…');
        } else if (value == 'import') {
          final n = await importFromFile(store);
          if (!mounted) return;
          if (n == null) {
            _snack('Nie wczytano pliku.');
          } else {
            setState(() {});
            _snack('Wczytano $n ${_recipeWord(n)}. 🎉');
          }
        }
      },
      itemBuilder: (_) => const [
        PopupMenuItem(
          value: 'export',
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.download_outlined, color: AppColors.olive),
            title: Text('Zapisz kopię (eksport)'),
          ),
        ),
        PopupMenuItem(
          value: 'import',
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.upload_outlined, color: AppColors.olive),
            title: Text('Wczytaj kopię (import)'),
          ),
        ),
      ],
    );
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  String _recipeWord(int n) {
    if (n == 1) return 'przepis';
    final mod10 = n % 10, mod100 = n % 100;
    if (mod10 >= 2 && mod10 <= 4 && (mod100 < 12 || mod100 > 14)) {
      return 'przepisy';
    }
    return 'przepisów';
  }

  Widget _searchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: TextField(
        onChanged: (v) => setState(() => _query = v),
        decoration: const InputDecoration(
          hintText: 'Szukaj przepisu lub składnika…',
          prefixIcon: Icon(Icons.search, color: AppColors.muted),
        ),
      ),
    );
  }

  Widget _categoryChips() {
    final chips = <String>[_allFilter, _favFilter, ...store.categories];
    return SizedBox(
      height: 52,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        itemCount: chips.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final c = chips[i];
          final selected = c == _filter;
          return ChoiceChip(
            label: Text(c),
            selected: selected,
            showCheckmark: false,
            selectedColor: AppColors.terracotta,
            labelStyle: TextStyle(
              color: selected ? Colors.white : AppColors.brown,
              fontWeight: FontWeight.w600,
            ),
            onSelected: (_) => setState(() => _filter = c),
          );
        },
      ),
    );
  }

  Widget _emptyState() {
    final searching = _query.isNotEmpty || _filter != _allFilter;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(searching ? '🔎' : '🥘', style: const TextStyle(fontSize: 64)),
            const SizedBox(height: 16),
            Text(
              searching ? 'Nic tu nie znalazłem' : 'Tu będą Twoje przepisy',
              style: AppTheme.heading(22),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              searching
                  ? 'Spróbuj innego słowa albo kategorii.'
                  : 'Dodaj pierwszy przepis ze zdjęciem i rolką wideo.',
              style: const TextStyle(color: AppColors.muted, fontSize: 15),
              textAlign: TextAlign.center,
            ),
            if (!searching) ...[
              const SizedBox(height: 20),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.terracotta,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
                ),
                onPressed: () => _openEditor(),
                icon: const Icon(Icons.add),
                label: const Text('Dodaj pierwszy przepis'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
