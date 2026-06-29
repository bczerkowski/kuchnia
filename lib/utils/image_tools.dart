import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

/// Zmniejsza obraz do maks. [maxSide] px (dłuższy bok) i koduje jako JPEG.
/// Dzięki temu zdjęcia z telefonu (np. 4000 px) nie zajmują kilku MB.
/// Zwraca base64 (bez prefiksu `data:`).
Future<String> downscaleToBase64(
  Uint8List bytes, {
  int maxSide = 1280,
  double quality = 0.82,
}) {
  final completer = Completer<String>();
  final blob = web.Blob([bytes.toJS].toJS);
  final url = web.URL.createObjectURL(blob);
  final img = web.HTMLImageElement();

  img.onload = ((web.Event _) {
    try {
      var w = img.naturalWidth;
      var h = img.naturalHeight;
      if (w == 0 || h == 0) {
        w = maxSide;
        h = maxSide;
      }
      final longSide = w > h ? w : h;
      final scale = longSide > maxSide ? maxSide / longSide : 1.0;
      final tw = (w * scale).round();
      final th = (h * scale).round();

      final canvas = web.HTMLCanvasElement()
        ..width = tw
        ..height = th;
      final ctx = canvas.getContext('2d') as web.CanvasRenderingContext2D;
      // Białe tło — JPEG nie ma przezroczystości.
      ctx.fillStyle = '#FFFFFF'.toJS;
      ctx.fillRect(0, 0, tw, th);
      ctx.drawImage(img, 0, 0, tw, th);

      final dataUrl = canvas.toDataURL('image/jpeg', quality.toJS);
      web.URL.revokeObjectURL(url);
      completer.complete(dataUrl.split(',').last);
    } catch (e) {
      web.URL.revokeObjectURL(url);
      completer.completeError(e);
    }
  }).toJS;

  img.onerror = ((web.Event _) {
    web.URL.revokeObjectURL(url);
    completer.completeError('Nie udało się odczytać obrazu.');
  }).toJS;

  img.src = url;
  return completer.future;
}

/// Próbuje odczytać obraz ze schowka (przycisk „Wklej"). Wymaga zgody
/// przeglądarki — wywoływane w odpowiedzi na kliknięcie użytkownika.
Future<Uint8List?> readClipboardImageBytes() async {
  try {
    final clipboard = web.window.navigator.clipboard;
    final items = (await clipboard.read().toDart).toDart;
    for (final item in items) {
      final types = item.types.toDart;
      for (final t in types) {
        final type = t.toDart;
        if (type.startsWith('image/')) {
          final blob = await item.getType(type).toDart;
          final buf = await blob.arrayBuffer().toDart;
          return buf.toDart.asUint8List();
        }
      }
    }
  } catch (_) {/* brak obrazu w schowku albo brak zgody */}
  return null;
}

/// Nasłuch zdarzenia „paste" (Ctrl+V) na całym dokumencie. Gdy w schowku
/// jest obraz, wywołuje [onImage] z jego bajtami.
web.EventListener? _pasteListener;

void attachPasteListener(void Function(Uint8List bytes) onImage) {
  detachPasteListener();
  _pasteListener = ((web.Event e) {
    final ce = e as web.ClipboardEvent;
    final items = ce.clipboardData?.items;
    if (items == null) return;
    for (var i = 0; i < items.length; i++) {
      final it = items[i];
      if (it.type.startsWith('image/')) {
        final file = it.getAsFile();
        if (file != null) {
          e.preventDefault();
          file.arrayBuffer().toDart.then((buf) {
            onImage(buf.toDart.asUint8List());
          });
          return;
        }
      }
    }
  }).toJS;
  web.document.addEventListener('paste', _pasteListener);
}

void detachPasteListener() {
  if (_pasteListener != null) {
    web.document.removeEventListener('paste', _pasteListener);
    _pasteListener = null;
  }
}
