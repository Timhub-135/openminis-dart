import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:openminis_core/openminis.dart' show PendingShare, ShareInbox;

/// Reads an incoming Android share intent (ACTION_SEND) delivered to the native
/// MainActivity and converts it into a [PendingShare] the UI can route into a
/// session. No-op on web/non-Android (returns null).
class ShareIntentHandler {
  static const _channel = MethodChannel('openminis/share');

  /// Try to consume a pending share from native (Android). Returns null if
  /// there is none (not launched via a share, or not on Android).
  static Future<PendingShare?> consume() async {
    try {
      final raw = await _channel.invokeMethod<String>('consumeShare');
      if (raw == null) return null;
      final map = (jsonDecode(raw) as Map).cast<String, dynamic>();
      // Reconstruct the share from extras the same way `ShareInbox` does.
      return ShareInbox.fromShareExtras(
        sharedText: map['sharedText'] as String?,
        sharedSubject: map['sharedSubject'] as String?,
        sharedFilePaths: (map['sharedUris'] as List?)
            ?.map((u) => u.toString())
            .toList(),
      );
    } on PlatformException {
      return null; // not on Android or channel unavailable
    } catch (_) {
      return null;
    }
  }
}
