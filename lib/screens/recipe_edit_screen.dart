import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../data/store.dart';
import '../models/recipe.dart';
import '../theme.dart';
import '../utils/image_tools.dart';
import 'crop_screen.dart';

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
  late final TextEditingController _steps;
  late final TextEditingController _video;
  late final TextEditingController _prep;
  late final TextEditingController _servings;

  // Składniki jako lista pól — każda pozycja to osobny wiersz.
  final List<TextEditingController> _ingredientCtrls = [];

  late String _category;
  String? _imageBase64;

  RecipeStore get store => widget.store;
  bool get _isNew => widget.existing == null;

  bool _processing = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _title = TextEditingController(text: e?.title ?? '');
    _steps = TextEditingController(text: e?.steps ?? '');
    _video = TextEditingController(text: e?.videoUrl ?? '');
    _prep = TextEditingController(text: e?.prepTime ?? '');
    _servings = TextEditingController(text: e?.servings ?? '');
    _imageBase64 = e?.imageBase64;
    _category = e?.category ??
        (store.categories.isNotEmpty ? store.categories.first : 'Obiad');

    // Zamień zapisany tekst składników na osobne wiersze.
    final lines = (e?.ingredients ?? '')
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();
    for (final l in lines) {
      _ingredientCtrls.add(TextEditingController(text: l));
    }
    if (_ingredientCtrls.isEmpty) {
      _ingredientCtrls.add(TextEditingController());
    }

    // Ctrl+V w dowolnym miejscu wklei zdjęcie ze schowka.
    attachPasteListener(_applyImageBytes);
  }

  @override
  void dispose() {
    detachPasteListener();
    _title.dispose();
    _steps.dispose();
    _video.dispose();
    _prep.dispose();
    _servings.dispose();
    for (final c in _ingredientCtrls) {
      c.dispose();
    }
    super.dispose();
  }

  /// Wspólna ścieżka dla wyboru i wklejenia obrazu: zmniejsza, otwiera
  /// kadrowanie (4:3), a wynik zapisuje jako base64.
  Future<void> _applyImageBytes(Uint8List bytes) async {
    setState(() => _processing = true);
    try {
      // Najpierw zmniejszamy (szybsze kadrowanie), potem dekodujemy do bajtów.
      final smallB64 = await downscaleToBase64(bytes);
      if (!mounted) return;
      final toCrop = base64Decode(smallB64);
      final cropped = await Navigator.of(context).push<Uint8List>(
        MaterialPageRoute(builder: (_) => CropScreen(bytes: toCrop)),
      );
      if (!mounted) return;
      final result = cropped ?? toCrop; // anulowanie kadru = bierz całość
      final finalB64 = await downscaleToBase64(result, maxSide: 1280);
      if (mounted) setState(() => _imageBase64 = finalB64);
    } catch (e) {
      if (mounted) _snack('Nie udało się przetworzyć zdjęcia.');
    } finally {
      if (mounted) setState(() => _processing = false);
    }
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _pickImage() async {
    try {
      final picker = ImagePicker();
      final file = await picker.pickImage(source: ImageSource.gallery);
      if (file == null) return;
      final Uint8List bytes = await file.readAsBytes();
      await _applyImageBytes(bytes);
    } catch (e) {
      if (mounted) _snack('Nie udało się wczytać zdjęcia.');
    }
  }

  Future<void> _pasteImage() async {
    final bytes = await readClipboardImageBytes();
    if (bytes == null) {
      if (mounted) {
        _snack('Brak obrazu w schowku. Skopiuj zdjęcie i spróbuj ponownie.');
      }
      return;
    }
    await _applyImageBytes(bytes);
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
    final ingredients = _ingredientCtrls
        .map((c) => c.text.trim())
        .where((t) => t.isNotEmpty)
        .join('\n');
    final recipe = Recipe(
      id: e?.id ?? store.newId(),
      title: _title.text.trim(),
      category: _category,
      ingredients: ingredients,
      steps: _steps.text.trim(),
      prepTime: _prep.text.trim(),
      servings: _servings.text.trim(),
      imageBase64: _imageBase64,
      videoUrl: _video.text.trim().isEmpty ? null : _video.text.trim(),
      favorite: e?.favorite ?? false,
      createdAt: e?.createdAt ?? DateTime.now().millisecondsSinceEpoch,
    );
    await store.save(recipe);
    if (mounted) Navigator.pop(context);
  }

  void _addIngredient() {
    setState(() => _ingredientCtrls.add(TextEditingController()));
  }

  void _removeIngredient(int i) {
    setState(() {
      _ingredientCtrls[i].dispose();
      _ingredientCtrls.removeAt(i);
      if (_ingredientCtrls.isEmpty) {
        _ingredientCtrls.add(TextEditingController());
      }
    });
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
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
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
            const SizedBox(height: 16),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _miniField(
                    label: 'Czas przygotowania',
                    controller: _prep,
                    hint: 'np. 15 min',
                    icon: Icons.schedule,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _miniField(
                    label: 'Liczba porcji',
                    controller: _servings,
                    hint: 'np. 4',
                    icon: Icons.restaurant,
                    keyboardType: TextInputType.number,
                  ),
                ),
              ],
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
            _ingredientsList(),
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
          ],
        ),
      ),
      // Przyklejony pasek zapisu — zawsze widoczny na dole.
      bottomNavigationBar: _saveBar(),
    );
  }

  Widget _saveBar() {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.cream,
        border: Border(top: BorderSide(color: AppColors.line)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
          child: FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.terracotta,
              minimumSize: const Size.fromHeight(54),
              shape:
                  RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            ),
            onPressed: _save,
            icon: const Icon(Icons.check),
            label: Text(_isNew ? 'Zapisz przepis' : 'Zapisz zmiany',
                style:
                    const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
          ),
        ),
      ),
    );
  }

  Widget _miniField({
    required String label,
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    TextInputType? keyboardType,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label(label),
        TextFormField(
          controller: controller,
          keyboardType: keyboardType,
          decoration: InputDecoration(
            hintText: hint,
            prefixIcon: Icon(icon, color: AppColors.muted, size: 20),
          ),
        ),
      ],
    );
  }

  Widget _ingredientsList() {
    return Column(
      children: [
        for (int i = 0; i < _ingredientCtrls.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              children: [
                const Padding(
                  padding: EdgeInsets.only(right: 10),
                  child: Icon(Icons.check_box_outline_blank,
                      color: AppColors.olive, size: 22),
                ),
                Expanded(
                  child: TextFormField(
                    controller: _ingredientCtrls[i],
                    textCapitalization: TextCapitalization.sentences,
                    textInputAction: TextInputAction.next,
                    onFieldSubmitted: (_) {
                      if (i == _ingredientCtrls.length - 1) _addIngredient();
                    },
                    decoration: const InputDecoration(
                      isDense: true,
                      hintText: 'np. 2 jajka',
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Usuń składnik',
                  icon: const Icon(Icons.close, color: AppColors.muted),
                  onPressed: () => _removeIngredient(i),
                ),
              ],
            ),
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: _addIngredient,
            style: TextButton.styleFrom(foregroundColor: AppColors.olive),
            icon: const Icon(Icons.add),
            label: const Text('Dodaj składnik',
                style: TextStyle(fontWeight: FontWeight.w700)),
          ),
        ),
      ],
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GestureDetector(
          onTap: hasImage ? null : _pickImage,
          child: Container(
            height: 230,
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
            child: _processing
                ? const Center(
                    child: CircularProgressIndicator(color: AppColors.terracotta))
                : (hasImage
                    ? null
                    : const Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.add_a_photo_outlined,
                              size: 44, color: AppColors.honey),
                          SizedBox(height: 10),
                          Text('Dodaj zdjęcie potrawy',
                              style: TextStyle(
                                  color: AppColors.muted,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 16)),
                          SizedBox(height: 4),
                          Text('wybierz plik albo wklej Ctrl+V',
                              style: TextStyle(
                                  color: AppColors.muted, fontSize: 13)),
                        ],
                      )),
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.brown,
                  side: const BorderSide(color: AppColors.line),
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
                onPressed: _processing ? null : _pickImage,
                icon: const Icon(Icons.photo_library_outlined, size: 20),
                label: Text(hasImage ? 'Zmień' : 'Wybierz'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.olive,
                  side: const BorderSide(color: AppColors.line),
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
                onPressed: _processing ? null : _pasteImage,
                icon: const Icon(Icons.content_paste, size: 20),
                label: const Text('Wklej (Ctrl+V)'),
              ),
            ),
            if (hasImage) ...[
              const SizedBox(width: 10),
              IconButton(
                tooltip: 'Usuń zdjęcie',
                style: IconButton.styleFrom(
                  foregroundColor: AppColors.terracotta,
                  side: const BorderSide(color: AppColors.line),
                  padding: const EdgeInsets.all(13),
                ),
                onPressed: () => setState(() => _imageBase64 = null),
                icon: const Icon(Icons.delete_outline),
              ),
            ],
          ],
        ),
      ],
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
