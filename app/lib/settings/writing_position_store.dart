import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Persists how far through a Writing-Document post's story the user has
/// scrolled in `WritingReaderScreen`, so re-opening it resumes near the
/// same spot -- `shared_preferences`, same shape as every other
/// `*SettingsStore` in this directory, but keyed per-post rather than one
/// global value: a single JSON-encoded `Map<String, double>` (post id as a
/// string key, since JSON object keys are always strings) under one
/// `shared_preferences` key.
///
/// The stored value is a 0.0-1.0 fraction of the reader's total scrollable
/// extent, not a raw pixel offset -- a pixel offset would point somewhere
/// different after the device's screen size or the user's font-scale
/// setting changes, while a fraction stays meaningful (this is explicitly
/// a "resume near the same spot" feature, not a byte-exact bookmark).
class WritingPositionStore {
  static const _key = 'writing_reader_positions';

  const WritingPositionStore();

  /// Null if [postId] has no saved position yet.
  Future<double?> getPosition(int postId) async {
    final positions = await _loadAll();
    return positions[postId.toString()];
  }

  Future<void> savePosition(int postId, double fraction) async {
    final positions = await _loadAll();
    positions[postId.toString()] = fraction.clamp(0.0, 1.0);
    await _saveAll(positions);
  }

  Future<Map<String, double>> _loadAll() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) {
      return {};
    }
    try {
      final decoded = jsonDecode(raw) as Map<String, Object?>;
      return decoded.map((key, value) => MapEntry(key, (value as num).toDouble()));
    } catch (_) {
      // Malformed/foreign-shaped stored value -- treat as "nothing saved
      // yet" rather than crashing the reader screen on open.
      return {};
    }
  }

  Future<void> _saveAll(Map<String, double> positions) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(positions));
  }
}
