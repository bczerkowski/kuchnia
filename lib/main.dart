import 'package:flutter/material.dart';

import 'data/store.dart';
import 'screens/home_screen.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final store = RecipeStore();
  await store.init();
  runApp(KuchniaApp(store: store));
}

class KuchniaApp extends StatelessWidget {
  final RecipeStore store;
  const KuchniaApp({super.key, required this.store});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Moja Kuchnia',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.build(),
      home: HomeScreen(store: store),
    );
  }
}
