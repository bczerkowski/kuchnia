import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

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

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 300,
            pinned: true,
            backgroundColor: AppColors.cream,
            foregroundColor: Colors.white,
            actions: [
              IconButton(
                tooltip: r.favorite ? 'Usuń z ulubionych' : 'Dodaj do ulubionych',
                icon: Icon(r.favorite ? Icons.favorite : Icons.favorite_border),
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
                    builder: (_) =>
                        RecipeEditScreen(store: store, existing: r),
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
            flexibleSpace: FlexibleSpaceBar(
              background: _headerImage(r),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 60),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _categoryPill(r.category),
                  const SizedBox(height: 12),
                  Text(r.title, style: AppTheme.heading(30)),
                  const SizedBox(height: 18),
                  if (r.videoUrl != null && r.videoUrl!.trim().isNotEmpty)
                    _videoButton(r.videoUrl!.trim()),
                  if (r.ingredients.trim().isNotEmpty) ...[
                    const SizedBox(height: 24),
                    _section('🧺  Składniki', r.ingredients, bullets: true),
                  ],
                  if (r.steps.trim().isNotEmpty) ...[
                    const SizedBox(height: 24),
                    _section('👩‍🍳  Przygotowanie', r.steps, bullets: false),
                  ],
                  if (r.ingredients.trim().isEmpty && r.steps.trim().isEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text('Brak treści przepisu — dodaj ją przyciskiem ✎.',
                          style: TextStyle(color: AppColors.muted)),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _headerImage(Recipe r) {
    if (r.imageBase64 != null && r.imageBase64!.isNotEmpty) {
      try {
        return Stack(
          fit: StackFit.expand,
          children: [
            Image.memory(base64Decode(r.imageBase64!), fit: BoxFit.cover),
            // Delikatne przyciemnienie u góry, żeby ikony były czytelne.
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.center,
                  colors: [Color(0x66000000), Colors.transparent],
                ),
              ),
            ),
          ],
        );
      } catch (_) {/* fallback poniżej */}
    }
    return Container(
      color: const Color(0xFFF3E7D6),
      child: const Center(
        child: Icon(Icons.restaurant_menu, size: 72, color: AppColors.honey),
      ),
    );
  }

  Widget _categoryPill(String category) {
    return Container(
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

  Widget _section(String title, String body, {required bool bullets}) {
    final lines = body
        .split('\n')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
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
          Text(title, style: AppTheme.heading(20)),
          const SizedBox(height: 12),
          if (bullets)
            ...lines.map((l) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Padding(
                        padding: EdgeInsets.only(top: 7, right: 10),
                        child: CircleAvatar(
                            radius: 3, backgroundColor: AppColors.terracotta),
                      ),
                      Expanded(
                        child: Text(l,
                            style: const TextStyle(fontSize: 16, height: 1.4)),
                      ),
                    ],
                  ),
                ))
          else
            Text(
              lines.join('\n'),
              style: const TextStyle(fontSize: 16, height: 1.55),
            ),
        ],
      ),
    );
  }
}
