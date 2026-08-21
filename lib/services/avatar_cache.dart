import 'package:flutter/foundation.dart';
import 'dart:io';

import 'package:crypto/crypto.dart' as crypto;
import 'package:http/http.dart' as http;

import '../models/models.dart';
import 'screen_time.dart';

/// Downloads profile photos into the shared app group so the home-screen
/// widget can draw them — WidgetKit has no network access.
class AvatarCache {
  AvatarCache._();

  /// Returns a map of profile id to a filename inside the app group,
  /// for whoever has a photo. Skips anyone already cached at that URL.
  static Future<Map<String, String>> cache(List<Profile> people) async {
    final dir = await ScreenTime.appGroupPath();
    if (dir == null) {
      debugPrint('AVATAR CACHE: no app group path');
      await ScreenTime.log('avatar cache: no app group path');
      return const {};
    }

    final out = <String, String>{};
    for (final p in people) {
      final url = p.avatarUrl;
      if (url == null || url.isEmpty) continue;
      // Name the file after a hash of the URL so a changed photo — which
      // carries a new cache-busting suffix — lands in a new file.
      final digest = crypto.md5.convert(url.codeUnits).toString();
      final name = 'avatar_$digest.jpg';
      final file = File('$dir/$name');
      try {
        if (!await file.exists()) {
          final res = await http.get(Uri.parse(url));
          if (res.statusCode != 200) continue;
          await file.writeAsBytes(res.bodyBytes);
        }
        out[p.id] = name;
      } catch (e) {
        // Skip this one; initials will show instead.
        debugPrint('AVATAR CACHE failed for ' + p.id + ': ' + e.toString());
        await ScreenTime.log('avatar cache failed: ' + e.toString());
      }
    }
    return out;
  }
}
