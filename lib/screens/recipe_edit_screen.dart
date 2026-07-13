import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../data/store.dart';
import '../models/recipe.dart';
import '../theme.dart';
import '../utils/image_tools.dart';

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
  final List<String> _images = []; // base64, pierwsze = okładka

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
    _images.addAll(e?.images ?? const []);
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

  /// Zmniejsza obraz i DOPISUJE go do listy zdjęć (można mieć wiele).
  Future<void> _applyImageBytes(Uint8List bytes) async {
    setState(() => _processing = true);
    try {
      final b64 = await downscaleToBase64(bytes, maxSide: 1280);
      if (mounted) setState(() => _images.add(b64));
    } catch (e) {
      if (mounted) _snack('Nie udało się przetworzyć zdjęcia.');
    } finally {
      if (mounted) setState(() => _processing = false);
    }
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  /// Wybór wielu zdjęć naraz z galerii.
  Future<void> _pickImages() async {
    try {
      final picker = ImagePicker();
      final files = await picker.pickMultiImage();
      if (files.isEmpty) return;
      setState(() => _processing = true);
      for (final f in files) {
        final bytes = await f.readAsBytes();
        final b64 = await downscaleToBase64(bytes, maxSide: 1280);
        if (!mounted) return;
        setState(() => _images.add(b64));
      }
    } catch (e) {
      if (mounted) _snack('Nie udało się wczytać zdjęć.');
    } finally {
      if (mounted) setState(() => _processing = false);
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

  void _addPhotoSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.cream,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined,
                  color: AppColors.olive),
              title: const Text('Wybierz z galerii'),
              subtitle: const Text('Możesz zaznaczyć kilka naraz'),
              onTap: () {
                Navigator.pop(context);
                _pickImages();
              },
            ),
            ListTile(
              leading: const Icon(Icons.content_paste, color: AppColors.olive),
              title: const Text('Wklej ze schowka'),
              subtitle: const Text('Skopiowane zdjęcie (Ctrl+V)'),
              onTap: () {
                Navigator.pop(context);
                _pasteImage();
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
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
      images: _images,
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
            _label('Zdjęcia'),
            _photoStrip(),
            if (_images.length > 1)
              const Padding(
                padding: EdgeInsets.only(top: 6, left: 2),
                child: Text(
                  'Pierwsze zdjęcie to okładka. Stuknij „Okładka" na innym, '
                  'aby ustawić je jako główne.',
                  style: TextStyle(color: AppColors.muted, fontSize: 12),
                ),
              ),
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
                Padding(
                  padding: const EdgeInsets.only(right: 10),
                  child: Icon(
                    Icons.check_box_outline_blank,
                    color: _ingredientCtrls[i]
                            .text
                            .toLowerCase()
                            .contains('opcjonaln')
                        ? AppColors.honey
                        : AppColors.olive,
                    size: 22,
                  ),
                ),
                Expanded(
                  child: TextFormField(
                    controller: _ingredientCtrls[i],
                    textCapitalization: TextCapitalization.sentences,
                    textInputAction: TextInputAction.next,
                    onChanged: (_) => setState(() {}),
                    onFieldSubmitted: (_) {
                      if (i == _ingredientCtrls.length - 1) _addIngredient();
                    },
                    decoration: const InputDecoration(
                      isDense: true,
                      hintText: 'np. 2 jajka (albo „opcjonalnie …")',
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

  Widget _photoStrip() {
    return SizedBox(
      height: 132,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          _addPhotoTile(),
          for (var i = 0; i < _images.length; i++)
            Padding(
              padding: const EdgeInsets.only(left: 10),
              child: _thumb(i),
            ),
        ],
      ),
    );
  }

  Widget _thumb(int i) {
    return Stack(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Image.memory(
            base64Decode(_images[i]),
            width: 112,
            height: 132,
            fit: BoxFit.cover,
            gaplessPlayback: true,
          ),
        ),
        Positioned(
          top: 6,
          right: 6,
          child: GestureDetector(
            onTap: () => setState(() => _images.removeAt(i)),
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: const BoxDecoration(
                  color: Colors.black54, shape: BoxShape.circle),
              child: const Icon(Icons.close, size: 16, color: Colors.white),
            ),
          ),
        ),
        if (i == 0)
          Positioned(
            left: 6,
            bottom: 6,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                  color: AppColors.terracotta,
                  borderRadius: BorderRadius.circular(20)),
              child: const Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.star_rounded, size: 12, color: Colors.white),
                SizedBox(width: 3),
                Text('Okładka',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700)),
              ]),
            ),
          )
        else
          // Na pozostałych zdjęciach: ustaw jako okładkę (przenosi na początek).
          Positioned(
            left: 6,
            bottom: 6,
            child: GestureDetector(
              onTap: () => setState(() {
                final img = _images.removeAt(i);
                _images.insert(0, img);
              }),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.55),
                    borderRadius: BorderRadius.circular(20)),
                child: const Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.star_outline_rounded, size: 12, color: Colors.white),
                  SizedBox(width: 3),
                  Text('Okładka',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700)),
                ]),
              ),
            ),
          ),
      ],
    );
  }

  Widget _addPhotoTile() {
    return GestureDetector(
      onTap: _processing ? null : _addPhotoSheet,
      child: Container(
        width: 112,
        height: 132,
        decoration: BoxDecoration(
          color: const Color(0xFFF3E7D6),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.line),
        ),
        child: _processing
            ? const Center(
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: AppColors.terracotta))
            : const Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.add_a_photo_outlined,
                      color: AppColors.honey, size: 30),
                  SizedBox(height: 8),
                  Text('Dodaj zdjęcia',
                      style: TextStyle(
                          color: AppColors.muted,
                          fontWeight: FontWeight.w600,
                          fontSize: 12.5)),
                ],
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
