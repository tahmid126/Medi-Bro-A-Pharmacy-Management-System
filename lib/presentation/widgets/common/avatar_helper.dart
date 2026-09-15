import 'dart:convert';
import 'package:flutter/material.dart';

/// Safely provides an ImageProvider for any avatar representation:
/// - null/empty -> returns null (caller shows initial letter)
/// - 'data:image/...;base64,...' -> returns MemoryImage
/// - 'http://...' or 'https://...' -> returns NetworkImage
ImageProvider? getAvatarImageProvider(String? avatarUrl) {
  if (avatarUrl == null || avatarUrl.trim().isEmpty) {
    return null;
  }
  final clean = avatarUrl.trim();
  if (clean.startsWith('data:image')) {
    try {
      final commaIdx = clean.indexOf(',');
      if (commaIdx != -1) {
        final b64 = clean.substring(commaIdx + 1);
        return MemoryImage(base64Decode(b64));
      }
    } catch (_) {
      return null;
    }
  }
  if (clean.startsWith('http://') || clean.startsWith('https://')) {
    return NetworkImage(clean);
  }
  return null;
}
