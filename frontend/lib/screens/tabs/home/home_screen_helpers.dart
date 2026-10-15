import 'dart:convert';
import 'dart:typed_data';

Uint8List? decodeAppIconBase64(String? b64) {
  if (b64 == null || b64.isEmpty) return null;
  try {
    return Uint8List.fromList(base64Decode(b64));
  } catch (_) {
    return null;
  }
}

String formatIsoShort(String iso) {
  if (iso.length >= 16) {
    return 'Updated ${iso.substring(0, 16).replaceFirst('T', ' ')}';
  }
  return 'Updated recently';
}
