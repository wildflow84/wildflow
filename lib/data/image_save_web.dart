import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

/// 브라우저 다운로드로 저장한다. 성공하면 null, 실패하면 이유 글자.
Future<String?> saveImageToDevice(Uint8List bytes, String name) async {
  try {
    final isPng = bytes.length > 3 && bytes[0] == 0x89 && bytes[1] == 0x50;
    final blob = web.Blob([bytes.toJS].toJS, web.BlobPropertyBag(type: isPng ? 'image/png' : 'image/jpeg'));
    final url = web.URL.createObjectURL(blob);
    final a = web.HTMLAnchorElement()
      ..href = url
      ..download = '$name.${isPng ? 'png' : 'jpg'}';
    web.document.body?.append(a);
    a.click();
    a.remove();
    web.URL.revokeObjectURL(url);
    return null;
  } catch (_) {
    return '저장하지 못했어';
  }
}
