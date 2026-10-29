import 'dart:typed_data';

import 'package:flutter/foundation.dart' show compute;
import 'package:image/image.dart' as img;

/// 서버로 보낼 수 있는 크기(약 900KB 이하)의 JPEG 로 줄인다. 이미 작은 JPEG 는 그대로 둔다.
const couponImageMaxBytes = 900 * 1024;

bool _isJpeg(Uint8List b) => b.length > 3 && b[0] == 0xff && b[1] == 0xd8 && b[2] == 0xff;

/// 줄이기 계산은 화면이 멈추지 않게 별도 격리에서 한다. 줄일 수 없으면(이미지가 아님) null.
Future<Uint8List?> prepareCouponImage(Uint8List src) {
  if (src.length <= couponImageMaxBytes && _isJpeg(src)) return Future.value(src);
  return compute(shrinkImage, src);
}

/// 가로 1280px 이하, JPEG 품질 80부터 낮춰 가며 [couponImageMaxBytes] 안으로 맞춘다. 그래도 크면 더 작게 줄인다.
Uint8List? shrinkImage(Uint8List src) {
  final decoded = img.decodeImage(src);
  if (decoded == null) return null;
  for (final w in [1280, 1000, 800, 640]) {
    final work = decoded.width > w ? img.copyResize(decoded, width: w) : decoded;
    for (final q in [80, 65, 50]) {
      final out = Uint8List.fromList(img.encodeJpg(work, quality: q));
      if (out.length <= couponImageMaxBytes) return out;
    }
  }
  return null;
}
