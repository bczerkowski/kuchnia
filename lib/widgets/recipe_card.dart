import 'dart:convert';
import 'package:flutter/material.dart';

import '../models/recipe.dart';
import '../theme.dart';

/// Kafelek przepisu — duże zdjęcie, tytuł, kategoria, serduszko, znaczek rolki.
class RecipeCard extends StatelessWidget {
  final Recipe recipe;
  final VoidCallback onTap;
  final VoidCallback onToggleFavorite;

  const RecipeCard({
    super.key,
    required this.recipe,
    required this.onTap,
    required this.onToggleFavorite,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.card,
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: AppColors.line),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(21)),
                child: AspectRatio(
                  aspectRatio: 4 / 3,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      _Photo(recipe: recipe),
                      // Serduszko
                      Positioned(
                        top: 8,
                        right: 8,
                        child: _RoundButton(
                          icon: recipe.favorite ? Icons.favorite : Icons.favorite_border,
                          color: recipe.favorite ? AppColors.terracotta : Colors.white,
                          onTap: onToggleFavorite,
                        ),
                      ),
                      // Znaczek rolki
                      if (recipe.videoUrl != null && recipe.videoUrl!.trim().isNotEmpty)
                        const Positioned(
                          bottom: 8,
                          left: 8,
                          child: _Badge(icon: Icons.videocam_rounded, text: 'Rolka'),
                        ),
                      // Znaczek liczby zdjęć
                      if (recipe.images.length > 1)
                        Positioned(
                          bottom: 8,
                          right: 8,
                          child: _Badge(
                              icon: Icons.photo_library_rounded,
                              text: '${recipe.images.length}'),
                        ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            recipe.category.toUpperCase(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 11,
                              letterSpacing: 0.8,
                              fontWeight: FontWeight.w700,
                              color: AppColors.olive,
                            ),
                          ),
                        ),
                        if (recipe.prepTime.trim().isNotEmpty) ...[
                          const SizedBox(width: 8),
                          const Icon(Icons.schedule,
                              size: 13, color: AppColors.muted),
                          const SizedBox(width: 3),
                          Text(
                            recipe.prepTime.trim(),
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: AppColors.muted,
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      recipe.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppTheme.heading(19),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Photo extends StatelessWidget {
  final Recipe recipe;
  const _Photo({required this.recipe});

  @override
  Widget build(BuildContext context) {
    final cover = recipe.cover;
    if (cover != null && cover.isNotEmpty) {
      try {
        return Image.memory(
          base64Decode(cover),
          fit: BoxFit.cover,
          gaplessPlayback: true,
        );
      } catch (_) {/* poniżej fallback */}
    }
    // Bez zdjęcia — ciepłe tło z ikoną.
    return Container(
      color: const Color(0xFFF3E7D6),
      child: const Center(
        child: Icon(Icons.restaurant_menu, size: 44, color: AppColors.honey),
      ),
    );
  }
}

class _RoundButton extends StatelessWidget {
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  const _RoundButton({required this.icon, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withValues(alpha: 0.28),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(7),
          child: Icon(icon, size: 20, color: color),
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  final IconData icon;
  final String text;
  const _Badge({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(30),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: Colors.white),
          const SizedBox(width: 5),
          Text(text,
              style: const TextStyle(
                  color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}
