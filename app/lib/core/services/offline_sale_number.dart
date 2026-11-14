import 'dart:math';

import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Numbers for sales made without a connection, so the printed receipt carries the number the
/// sale will keep on the server: OFF-{location}-{yyMMdd}-{device}-{nnn}, e.g. OFF-BR01-261114-K7QX-001.
///
/// The device part is 4 random characters chosen once per install, so two phones selling offline
/// on the same day never produce the same number; nnn counts this device's offline sales that day.
class OfflineSaleNumber {
  static const _tagKey = 'offline_sale_device_tag';
  static const _seqKey = 'offline_sale_sequence';
  static const _alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'; // no 0/O, 1/I

  static Future<String> next(String? locationCode, {DateTime? now}) async {
    final prefs = await SharedPreferences.getInstance();
    var tag = prefs.getString(_tagKey);
    if (tag == null || tag.length != 4) {
      final random = Random.secure();
      tag = List.generate(4, (_) => _alphabet[random.nextInt(_alphabet.length)]).join();
      await prefs.setString(_tagKey, tag);
    }

    final day = DateFormat('yyMMdd').format(now ?? DateTime.now());
    final stored = prefs.getString(_seqKey);
    final last = stored != null && stored.startsWith('$day:') ? int.tryParse(stored.substring(day.length + 1)) ?? 0 : 0;
    final seq = last + 1;
    await prefs.setString(_seqKey, '$day:$seq');

    final code = (locationCode ?? '').toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
    final location = code.isEmpty ? 'LOK' : (code.length > 8 ? code.substring(0, 8) : code);
    return 'OFF-$location-$day-$tag-${seq.toString().padLeft(3, '0')}';
  }
}
