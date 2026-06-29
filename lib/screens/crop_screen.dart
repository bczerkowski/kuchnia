import 'dart:typed_data';

import 'package:crop_your_image/crop_your_image.dart';
import 'package:flutter/material.dart';

import '../theme.dart';

/// Prosty ekran kadrowania zdjęcia do proporcji 4:3 (przeciągaj i przybliżaj).
/// Zwraca wykadrowane bajty PNG albo null, jeśli anulowano.
class CropScreen extends StatefulWidget {
  final Uint8List bytes;
  const CropScreen({super.key, required this.bytes});

  @override
  State<CropScreen> createState() => _CropScreenState();
}

class _CropScreenState extends State<CropScreen> {
  final _controller = CropController();
  bool _busy = false;

  static const _bg = Color(0xFF2A211C);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        foregroundColor: Colors.white,
        title: const Text('Kadruj zdjęcie',
            style: TextStyle(color: Colors.white)),
        actions: [
          TextButton.icon(
            onPressed: _busy
                ? null
                : () {
                    setState(() => _busy = true);
                    _controller.crop();
                  },
            icon: const Icon(Icons.check, color: AppColors.honey),
            label: const Text('Gotowe',
                style: TextStyle(
                    color: AppColors.honey, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Crop(
              image: widget.bytes,
              controller: _controller,
              aspectRatio: 4 / 3,
              interactive: true,
              baseColor: _bg,
              maskColor: Colors.black.withValues(alpha: 0.55),
              cornerDotBuilder: (size, edgeAlignment) =>
                  const DotControl(color: AppColors.honey),
              onCropped: (result) {
                switch (result) {
                  case CropSuccess(:final croppedImage):
                    Navigator.pop(context, croppedImage);
                  case CropFailure():
                    if (mounted) {
                      setState(() => _busy = false);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                            content: Text('Nie udało się wykadrować zdjęcia.')),
                      );
                    }
                }
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 22),
            child: Text(
              'Przeciągaj i przybliżaj zdjęcie, aby ustawić ładny kadr.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white.withValues(alpha: 0.8)),
            ),
          ),
        ],
      ),
    );
  }
}
