import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

import 'store.dart';

/// Pobiera wszystkie przepisy jako plik JSON (kopia zapasowa).
void exportToFile(RecipeStore store) {
  final json = const JsonEncoder.withIndent('  ').convert(store.exportData());
  final today = DateTime.now();
  final stamp =
      '${today.year}-${_pad2(today.month)}-${_pad2(today.day)}';
  final filename = 'moja-kuchnia-przepisy-$stamp.json';

  final blob = web.Blob(
    [json.toJS].toJS,
    web.BlobPropertyBag(type: 'application/json;charset=utf-8'),
  );
  final url = web.URL.createObjectURL(blob);
  final a = web.document.createElement('a') as web.HTMLAnchorElement
    ..href = url
    ..download = filename;
  web.document.body!.appendChild(a);
  a.click();
  a.remove();
  web.URL.revokeObjectURL(url);
}

/// Otwiera okno wyboru pliku JSON i wczytuje przepisy.
/// Zwraca liczbę wczytanych przepisów, albo null jeśli anulowano/błąd.
Future<int?> importFromFile(RecipeStore store) async {
  final completer = Completer<int?>();

  final input = web.document.createElement('input') as web.HTMLInputElement
    ..type = 'file'
    ..accept = '.json,application/json';

  input.onchange = ((web.Event _) {
    final files = input.files;
    if (files == null || files.length == 0) {
      if (!completer.isCompleted) completer.complete(null);
      return;
    }
    final file = files.item(0)!;
    final reader = web.FileReader();
    // Callback dla JS musi być synchroniczny (void), więc pracę async
    // odpalamy wewnątrz osobnej, niezablokowanej funkcji.
    reader.onload = ((web.Event _) {
      Future(() async {
        try {
          final text = (reader.result as JSString).toDart;
          final data = jsonDecode(text);
          if (data is Map) {
            final n = await store.importData(data);
            if (!completer.isCompleted) completer.complete(n);
          } else {
            if (!completer.isCompleted) completer.complete(null);
          }
        } catch (_) {
          if (!completer.isCompleted) completer.complete(null);
        }
      });
    }).toJS;
    reader.onerror = ((web.Event _) {
      if (!completer.isCompleted) completer.complete(null);
    }).toJS;
    reader.readAsText(file);
  }).toJS;

  input.click();
  return completer.future;
}

String _pad2(int n) => n.toString().padLeft(2, '0');
