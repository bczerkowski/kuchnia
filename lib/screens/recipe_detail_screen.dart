import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../data/store.dart';
import '../models/recipe.dart';
import '../theme.dart';
import '../utils/video_link.dart';
import 'recipe_edit_screen.dart';

class RecipeDetailScreen extends StatefulWidget {
  final RecipeStore store;
  final String recipeId;
  const RecipeDetailScreen(
      {super.key, required this.store, required this.recipeId});

  @override
  State<RecipeDetailScreen> createState() => _RecipeDetailScreenState();
}

class _RecipeDetailScreenState extends State<RecipeDetailScreen> {
  RecipeStore get store => widget.store;

  // Odhaczone składniki (tylko na czas gotowania, niezapisywane).
  final Set<int> _checked = {};

  // Galeria zdjęć.
  final _pageCtrl = PageController();
  int _page = 0;

  @override
  void initState() {
    super.initState();
    // Ekran nie gaśnie podczas gotowania.
    WakelockPlus.enable().catchError((_) {});
  }

  @override
  void dispose() {
    _pageCtrl.dispose();
    WakelockPlus.disable().catchError((_) {});
    super.dispose();
  }

  void _goToPage(int t, int count) {
    final i = t.clamp(0, count - 1);
    _pageCtrl.animateToPage(i,
        duration: const Duration(milliseconds: 280), curve: Curves.easeOut);
  }

  Future<void> _openVideo(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nie udało się otworzyć linku.')),
      );
    }
  }

  Future<void> _confirmDelete(Recipe r) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Usunąć przepis?'),
        content: Text('„${r.title}" zniknie na dobre.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Anuluj'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.terracotta),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Usuń'),
          ),
        ],
      ),
    );
    if (yes == true) {
      await store.delete(r.id);
      if (mounted) Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = store.byId(widget.recipeId);
    if (r == null) {
      return const Scaffold(body: Center(child: Text('Przepis nie istnieje.')));
    }

    final ingredients = r.ingredients
        .split('\n')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();

    return Scaffold(
      // Smukły, przezroczysty pasek na tle kremu — same ikony, bez „belki".
      appBar: AppBar(
        backgroundColor: AppColors.cream,
        elevation: 0,
        scrolledUnderElevation: 0,
        iconTheme: const IconThemeData(color: AppColors.brown, size: 26),
        leading: IconButton(
          tooltip: 'Wstecz',
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            tooltip: r.favorite ? 'Usuń z ulubionych' : 'Dodaj do ulubionych',
            icon: Icon(r.favorite ? Icons.favorite : Icons.favorite_border),
            color: r.favorite ? AppColors.terracotta : AppColors.brown,
            iconSize: 26,
            onPressed: () async {
              await store.toggleFavorite(r);
              setState(() {});
            },
          ),
          IconButton(
            tooltip: 'Edytuj',
            icon: const Icon(Icons.edit),
            iconSize: 26,
            onPressed: () async {
              await Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => RecipeEditScreen(store: store, existing: r),
              ));
              if (mounted) setState(() {});
            },
          ),
          IconButton(
            tooltip: 'Usuń',
            icon: const Icon(Icons.delete_outline),
            iconSize: 26,
            onPressed: () => _confirmDelete(r),
          ),
          const SizedBox(width: 6),
        ],
      ),
      // Wyśrodkowana kolumna o stałej maks. szerokości — wygląda jak na telefonie.
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 60),
            children: [
              _photoCard(r),
              const SizedBox(height: 20),
              _categoryPill(r.category),
              const SizedBox(height: 12),
              Text(r.title, style: AppTheme.heading(30)),
              if (r.prepTime.trim().isNotEmpty ||
                  r.servings.trim().isNotEmpty) ...[
                const SizedBox(height: 14),
                _infoRow(r),
              ],
              const SizedBox(height: 18),
              if (r.videoUrl != null && r.videoUrl!.trim().isNotEmpty)
                _videoButton(r.videoUrl!.trim()),
              if (ingredients.isNotEmpty) ...[
                const SizedBox(height: 24),
                _ingredientsSection(ingredients),
              ],
              if (r.steps.trim().isNotEmpty) ...[
                const SizedBox(height: 24),
                _stepsSection(r.steps),
              ],
              if (ingredients.isEmpty && r.steps.trim().isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text('Brak treści przepisu — dodaj ją przyciskiem ✎.',
                      style: TextStyle(color: AppColors.muted)),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// Galeria zdjęć: estetyczna karta 4:3 (wyśrodkowana, zaokrąglona, z cieniem)
  /// z przeglądaniem wielu zdjęć — przesuwanie, strzałki, licznik i kropki.
  Widget _photoCard(Recipe r) {
    final images = r.images;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            boxShadow: [
              BoxShadow(
                color: AppColors.brown.withValues(alpha: 0.14),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: AspectRatio(
              aspectRatio: 4 / 3,
              child: images.isEmpty
                  ? _photoFallback()
                  : Stack(
                      fit: StackFit.expand,
                      children: [
                        PageView.builder(
                          controller: _pageCtrl,
                          itemCount: images.length,
                          onPageChanged: (i) => setState(() => _page = i),
                          itemBuilder: (_, i) => Image.memory(
                            base64Decode(images[i]),
                            fit: BoxFit.cover,
                            gaplessPlayback: true,
                            errorBuilder: (_, _, _) => _photoFallback(),
                          ),
                        ),
                        if (images.length > 1) ..._galleryControls(images.length),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _galleryControls(int count) {
    return [
      // Licznik „1 / N".
      Positioned(
        top: 12,
        right: 12,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.45),
            borderRadius: BorderRadius.circular(40),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.photo_library_rounded,
                size: 14, color: Colors.white),
            const SizedBox(width: 5),
            Text('${_page + 1} / $count',
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w600)),
          ]),
        ),
      ),
      // Strzałki (działają też myszą na desktopie).
      Positioned(
        left: 8,
        top: 0,
        bottom: 0,
        child: Center(
          child: _arrow(Icons.chevron_left_rounded, _page > 0,
              () => _goToPage(_page - 1, count)),
        ),
      ),
      Positioned(
        right: 8,
        top: 0,
        bottom: 0,
        child: Center(
          child: _arrow(Icons.chevron_right_rounded, _page < count - 1,
              () => _goToPage(_page + 1, count)),
        ),
      ),
      // Klikalne kropki.
      Positioned(
        bottom: 12,
        left: 0,
        right: 0,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(
            count,
            (i) => GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => _goToPage(i, count),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                margin: const EdgeInsets.symmetric(horizontal: 3, vertical: 6),
                width: i == _page ? 22 : 8,
                height: 8,
                decoration: BoxDecoration(
                  color: i == _page ? Colors.white : Colors.white60,
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ),
        ),
      ),
    ];
  }

  Widget _arrow(IconData icon, bool enabled, VoidCallback onTap) {
    return AnimatedOpacity(
      opacity: enabled ? 1 : 0,
      duration: const Duration(milliseconds: 200),
      child: IgnorePointer(
        ignoring: !enabled,
        child: Material(
          color: Colors.black.withValues(alpha: 0.4),
          shape: const CircleBorder(),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Icon(icon, color: Colors.white, size: 26),
            ),
          ),
        ),
      ),
    );
  }

  Widget _photoFallback() => Container(
        color: const Color(0xFFF3E7D6),
        child: const Center(
          child: Icon(Icons.restaurant_menu, size: 64, color: AppColors.honey),
        ),
      );

  Widget _categoryPill(String category) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: AppColors.olive.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(30),
        ),
        child: Text(
          category,
          style: const TextStyle(
              color: AppColors.olive, fontWeight: FontWeight.w700, fontSize: 13),
        ),
      ),
    );
  }

  Widget _infoRow(Recipe r) {
    final chips = <Widget>[];
    if (r.prepTime.trim().isNotEmpty) {
      chips.add(_infoChip(Icons.schedule, r.prepTime.trim()));
    }
    if (r.servings.trim().isNotEmpty) {
      chips.add(_infoChip(Icons.restaurant, '${r.servings.trim()} porcji'));
    }
    return Wrap(spacing: 10, runSpacing: 10, children: chips);
  }

  Widget _infoChip(IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: AppColors.line),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: AppColors.terracotta),
          const SizedBox(width: 7),
          Text(text,
              style: const TextStyle(
                  fontWeight: FontWeight.w700, color: AppColors.brown)),
        ],
      ),
    );
  }

  Widget _videoButton(String url) {
    final info = videoInfoFor(url);
    return SizedBox(
      width: double.infinity,
      child: FilledButton.icon(
        style: FilledButton.styleFrom(
          backgroundColor: info.color,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
        onPressed: () => _openVideo(url),
        icon: Icon(info.icon),
        label: Text(info.label,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
      ),
    );
  }

  Widget _ingredientsSection(List<String> lines) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('🧺  Składniki', style: AppTheme.heading(20)),
          const SizedBox(height: 6),
          for (int i = 0; i < lines.length; i++) _ingredientTile(i, lines[i]),
        ],
      ),
    );
  }

  Widget _ingredientTile(int i, String text) {
    final checked = _checked.contains(i);
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () => setState(() {
        if (checked) {
          _checked.remove(i);
        } else {
          _checked.add(i);
        }
      }),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              checked ? Icons.check_box : Icons.check_box_outline_blank,
              color: checked ? AppColors.olive : AppColors.muted,
              size: 24,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                text,
                style: TextStyle(
                  fontSize: 16,
                  height: 1.4,
                  color: checked ? AppColors.muted : AppColors.brown,
                  decoration:
                      checked ? TextDecoration.lineThrough : TextDecoration.none,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _stepsSection(String body) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('👩‍🍳  Przygotowanie', style: AppTheme.heading(20)),
          const SizedBox(height: 12),
          Text(
            body
                .split('\n')
                .map((e) => e.trim())
                .where((e) => e.isNotEmpty)
                .join('\n'),
            style: const TextStyle(fontSize: 16, height: 1.55),
          ),
        ],
      ),
    );
  }
}
