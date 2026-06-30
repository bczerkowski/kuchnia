/// Jeden przepis. Zdjęcie trzymamy jako base64 (żeby zostało na urządzeniu),
/// wideo to tylko link do rolki (Instagram / YouTube / TikTok).
class Recipe {
  final String id;
  String title;
  String category;
  String ingredients; // składniki (linia = jedna pozycja)
  String steps; // przygotowanie / przepis
  String prepTime; // czas przygotowania, np. „15 min" (opcjonalny)
  String servings; // liczba porcji, np. „4" (opcjonalna)
  List<String> images; // zdjęcia potrawy (base64, pierwsze = okładka)
  String? videoUrl; // link do rolki/filmu (opcjonalny)
  bool favorite;
  int createdAt; // millis

  Recipe({
    required this.id,
    required this.title,
    required this.category,
    this.ingredients = '',
    this.steps = '',
    this.prepTime = '',
    this.servings = '',
    List<String>? images,
    this.videoUrl,
    this.favorite = false,
    required this.createdAt,
  }) : images = images ?? <String>[];

  /// Okładka = pierwsze zdjęcie (na kafelku i jako miniatura).
  String? get cover => images.isNotEmpty ? images.first : null;

  Map<String, dynamic> toMap() => {
        'id': id,
        'title': title,
        'category': category,
        'ingredients': ingredients,
        'steps': steps,
        'prepTime': prepTime,
        'servings': servings,
        'images': images,
        'videoUrl': videoUrl,
        'favorite': favorite,
        'createdAt': createdAt,
      };

  factory Recipe.fromMap(Map map) => Recipe(
        id: map['id'] as String,
        title: (map['title'] ?? '') as String,
        category: (map['category'] ?? '') as String,
        ingredients: (map['ingredients'] ?? '') as String,
        steps: (map['steps'] ?? '') as String,
        prepTime: (map['prepTime'] ?? '') as String,
        servings: (map['servings'] ?? '') as String,
        images: (map['images'] as List?)?.map((e) => e as String).toList() ??
            // Zgodność wstecz: pojedyncze stare zdjęcie.
            ((map['imageBase64'] is String &&
                    (map['imageBase64'] as String).isNotEmpty)
                ? [map['imageBase64'] as String]
                : <String>[]),
        videoUrl: map['videoUrl'] as String?,
        favorite: (map['favorite'] ?? false) as bool,
        createdAt: (map['createdAt'] ?? 0) as int,
      );
}
