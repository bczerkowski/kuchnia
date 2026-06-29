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

  @override
  void initState() {
    super.initState();
    // Ekran nie gaśnie podczas gotowania.
    WakelockPlus.enable().catchError((_) {});
  }

  @override
  void dispose() {
    WakelockPlus.disable().catchError((_) {});
    super.dispose();
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
      appBar: AppBar(
        actions: [
          IconButton(
            tooltip: r.favorite ? 'Usuń z ulubionych' : 'Dodaj do ulubionych',
            icon: Icon(r.favorite ? Icons.favorite : Icons.favorite_border,
                color: r.favorite ? AppColors.terracotta : AppColors.brown),
            onPressed: () async {
              await store.toggleFavorite(r);
              setState(() {});
            },
          ),
          IconButton(
            tooltip: 'Edytuj',
            icon: const Icon(Icons.edit),
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
            onPressed: () => _confirmDelete(r),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 60),
        children: [
          _headerImage(r),
          const SizedBox(height: 18),
          _categoryPill(r.category),
          const SizedBox(height: 12),
          Text(r.title, style: AppTheme.heading(30)),
          if (r.prepTime.trim().isNotEmpty || r.servings.trim().isNotEmpty) ...[
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
    );
  }

  Widget _headerImage(Recipe r) {
    Widget inner;
    if (r.imageBase64 != null && r.imageBase64!.isNotEmpty) {
      try {
        inner = Image.memory(base64Decode(r.imageBase64!), fit: BoxFit.cover);
      } catch (_) {
        inner = _photoFallback();
      }
    } else {
      inner = _photoFallback();
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: AspectRatio(aspectRatio: 4 / 3, child: inner),
    );
  }

  Widget _photoFallback() => Container(
        color: const Color(0xFFF3E7D6),
        child: const Center(
          child: Icon(Icons.restaurant_menu, size: 72, color: AppColors.honey),
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
