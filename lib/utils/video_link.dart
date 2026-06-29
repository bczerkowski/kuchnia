import 'package:flutter/material.dart';

/// Rozpoznaje, skąd pochodzi rolka, żeby pokazać ładną etykietę i kolor.
enum VideoSource { youtube, instagram, tiktok, other }

class VideoInfo {
  final VideoSource source;
  final String label;
  final IconData icon;
  final Color color;
  const VideoInfo(this.source, this.label, this.icon, this.color);
}

VideoInfo videoInfoFor(String url) {
  final u = url.toLowerCase();
  if (u.contains('youtube.com') || u.contains('youtu.be')) {
    return const VideoInfo(VideoSource.youtube, 'Obejrzyj na YouTube',
        Icons.play_circle_fill, Color(0xFFE0392B));
  }
  if (u.contains('instagram.com')) {
    return const VideoInfo(VideoSource.instagram, 'Obejrzyj rolkę na Instagramie',
        Icons.play_circle_fill, Color(0xFFC13584));
  }
  if (u.contains('tiktok.com')) {
    return const VideoInfo(VideoSource.tiktok, 'Obejrzyj na TikToku',
        Icons.play_circle_fill, Color(0xFF010101));
  }
  return const VideoInfo(VideoSource.other, 'Obejrzyj wideo',
      Icons.play_circle_fill, Color(0xFFD0674A));
}
