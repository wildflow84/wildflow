import 'dart:typed_data';

import 'package:gal/gal.dart';

/// 갤러리에 저장한다. 성공하면 null, 실패하면 이유 글자.
Future<String?> saveImageToDevice(Uint8List bytes, String name) async {
  try {
    await Gal.putImageBytes(bytes, name: name);
    return null;
  } on GalException catch (e) {
    return e.type == GalExceptionType.accessDenied ? '사진 저장 권한이 없어. 설정에서 허용해줘' : '저장하지 못했어 (${e.type.name})';
  } catch (_) {
    return '저장하지 못했어';
  }
}
