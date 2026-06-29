import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../data/store.dart';
import '../models/recipe.dart';
import '../theme.dart';

class RecipeEditScreen extends StatefulWidget {
  final RecipeStore store;
  final Recipe? existing;
  const RecipeEditScreen({super.key, required this.store, this.existing});

  @override
  State<RecipeEditScreen> createState() => _RecipeEditScreenState();
}

class _RecipeEditScreenState extends State<RecipeEditScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _title;
  late final TextEditingController _ingredients;
  late final TextEditingController _steps;
  late final TextEditingController _video;

  late String _category;
  String? _imageBase64;

  RecipeStore get store => widget.store;
  bool get _isNew => widget.existing == null;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _title = TextEditingController(text: e?.title ?? '');
    _ingredients = TextEditingController(text: e?.ingredients ?? '');
    _steps = TextEditingController(text: e?.steps ?? '');
    _video = TextEditingController(text: e?.videoUrl ?? '');
    _imageBase64 = e?.imageBase64;
    _category = e?.category ??
        (store.categories.isNotEmpty ? store.categories.first : 'Obiad');
  }

  @override
  void dispose() {
    _title.dispose();
    _ingredients.dispose();
    _steps.dispose();
    _video.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    try {
      final picker = ImagePicker();
      final file = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1400,
        imageQuality: 82,
      );
      if (file == null) return;
      final Uint8List bytes = await file.readAsBytes();
      setState(() => _imageBase64 = base64Encode(bytes));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Nie udało się wczytać zdjęcia: $e')),
        );
      }
    }
  }

  Future<void> _addCategoryDialog() async {
    final ctrl = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Nowa kategoria'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'np. Zupy, Grill, Fit…'),
          onSubmitted: (v) => Navigator.pop(context, v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Anuluj'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.terracotta),
            onPressed: () => Navigator.pop(context, ctrl.text),
            child: const Text('Dodaj'),
          ),
        ],
      ),
    );
    if (name != null && name.trim().isNotEmpty) {
      await store.addCategory(name);
      setState(() => _category = name.trim());
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final e = widget.existing;
    final recipe = Recipe(
      id: e?.id ?? store.newId(),
      title: _title.text.trim(),
      category: _category,
      ingredients: _ingredients.text.trim(),
      steps: _steps.text.trim(),
      imageBase64: _imageBase64,
      videoUrl: _video.text.trim().isEmpty ? null : _video.text.trim(),
      favorite: e?.favorite ?? false,
      createdAt: e?.createdAt ?? DateTime.now().millisecondsSinceEpoch,
    );
    await store.save(recipe);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isNew ? 'Nowy przepis' : 'Edytuj przepis'),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
          children: [
            _photoPicker(),
            const SizedBox(height: 20),
            _label('Nazwa potrawy'),
            TextFormField(
              controller: _title,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(hintText: 'np. Naleśniki babci'),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Podaj nazwę przepisu' : null,
            ),
            const SizedBox(height: 20),
            _label('Kategoria'),
            _categorySelector(),
            const SizedBox(height: 20),
            _label('Link do rolki / wideo (opcjonalnie)'),
            TextFormField(
              controller: _video,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(
                hintText: 'Wklej link z Instagrama, YouTube lub TikToka',
                prefixIcon: Icon(Icons.link, color: AppColors.muted),
              ),
            ),
            const SizedBox(height: 20),
            _label('Składniki'),
            TextFormField(
              controller: _ingredients,
              minLines: 3,
              maxLines: 10,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                hintText: 'Każdy składnik w nowej linii:\n2 jajka\nszklanka mąki\n…',
              ),
            ),
            const SizedBox(height: 20),
            _label('Przygotowanie'),
            TextFormField(
              controller: _steps,
              minLines: 5,
              maxLines: 20,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                hintText: 'Opisz krok po kroku, jak to zrobić…',
              ),
            ),
            const SizedBox(height: 28),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.terracotta,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16)),
              ),
              onPressed: _save,
              icon: const Icon(Icons.check),
              label: Text(_isNew ? 'Zapisz przepis' : 'Zapisz zmiany',
                  style:
                      const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 8, left: 2),
        child: Text(text,
            style: const TextStyle(
                fontWeight: FontWeight.w700, color: AppColors.brown, fontSize: 15)),
      );

  Widget _photoPicker() {
    final hasImage = _imageBase64 != null && _imageBase64!.isNotEmpty;
    return GestureDetector(
      onTap: _pickImage,
      child: Container(
        height: 220,
        width: double.infinity,
        decoration: BoxDecoration(
          color: const Color(0xFFF3E7D6),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.line),
          image: hasImage
              ? DecorationImage(
                  image: MemoryImage(base64Decode(_imageBase64!)),
                  fit: BoxFit.cover,
                )
              : null,
        ),
        child: hasImage
            ? Align(
                alignment: Alignment.topRight,
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _imgButton(Icons.edit, 'Zmień', _pickImage),
                      const SizedBox(width: 8),
                      _imgButton(Icons.delete_outline, 'Usuń',
                          () => setState(() => _imageBase64 = null)),
                    ],
                  ),
                ),
              )
            : const Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.add_a_photo_outlined,
                      size: 40, color: AppColors.honey),
                  SizedBox(height: 10),
                  Text('Dodaj zdjęcie potrawy',
                      style: TextStyle(
                          color: AppColors.muted, fontWeight: FontWeight.w600)),
                ],
              ),
      ),
    );
  }

  Widget _imgButton(IconData icon, String label, VoidCallback onTap) {
    return Material(
      color: Colors.black.withValues(alpha: 0.5),
      borderRadius: BorderRadius.circular(30),
      child: InkWell(
        borderRadius: BorderRadius.circular(30),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: Colors.white),
              const SizedBox(width: 5),
              Text(label,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _categorySelector() {
    final cats = store.categories;
    return Row(
      children: [
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.line),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: cats.contains(_category) ? _category : null,
                isExpanded: true,
                borderRadius: BorderRadius.circular(16),
                items: cats
                    .map((c) =>
                        DropdownMenuItem(value: c, child: Text(c)))
                    .toList(),
                onChanged: (v) =>
                    setState(() => _category = v ?? _category),
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        IconButton.filledTonal(
          tooltip: 'Nowa kategoria',
          style: IconButton.styleFrom(
            backgroundColor: AppColors.olive.withValues(alpha: 0.15),
            foregroundColor: AppColors.olive,
            padding: const EdgeInsets.all(14),
          ),
          onPressed: _addCategoryDialog,
          icon: const Icon(Icons.add),
        ),
      ],
    );
  }
}
