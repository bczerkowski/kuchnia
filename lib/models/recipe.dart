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
  String? imageBase64; // zdjęcie potrawy (opcjonalne)
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
    this.imageBase64,
    this.videoUrl,
    this.favorite = false,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'title': title,
        'category': category,
        'ingredients': ingredients,
        'steps': steps,
        'prepTime': prepTime,
        'servings': servings,
        'imageBase64': imageBase64,
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
        imageBase64: map['imageBase64'] as String?,
        videoUrl: map['videoUrl'] as String?,
        favorite: (map['favorite'] ?? false) as bool,
        createdAt: (map['createdAt'] ?? 0) as int,
      );
}
