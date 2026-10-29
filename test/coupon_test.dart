import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:ourday/features/coupons/coupon.dart';
import 'package:ourday/features/coupons/image_prep.dart';
import 'package:ourday/features/feature_registry.dart';
import 'package:ourday/features/features_screen.dart';
import 'package:ourday/models/item.dart';

void main() {
  test('쿠폰번호 정규화: 서버와 같은 규칙', () {
    expect(normalizeCouponNumber('1234 5678-9012'), '123456789012');
    expect(normalizeCouponNumber(' ab12-cd34 ef56 '), 'AB12CD34EF56');
    expect(normalizeCouponNumber('12345'), isNull);
    expect(normalizeCouponNumber('1' * 33), isNull);
    expect(normalizeCouponNumber('12345678가'), isNull);
    expect(normalizeCouponNumber(''), isNull);
    expect(formatCouponNumber('123456789012'), '1234 5678 9012');
    expect(formatCouponNumber('AB12CD34'), 'AB12CD34');
  });

  test('할 일의 couponId: 서버가 넣은 값은 수정해도 유지되고, 없으면 쓰지 않는다', () {
    final todo = Item(id: 't', type: ItemType.todo, title: '쿠폰 판매 ····9012', start: DateTime(2026, 10, 29), ownerUid: 'mina', couponId: '123456789012');
    final done = todo.copyWith(done: true);
    expect(done.couponId, '123456789012');
    expect(done.toMap()['couponId'], '123456789012');
    expect(copyOfItem(todo).couponId, isNull); // 복제는 쿠폰과 무관
    final plain = Item(id: 'p', type: ItemType.todo, title: '일반', start: DateTime(2026, 10, 29), ownerUid: 'me');
    expect(plain.toMap().containsKey('couponId'), isFalse); // 일반 항목을 저장해도 couponId 를 건드리지 않는다
  });

  test('쿠폰 상태 표시', () {
    const c = Coupon(number: '123456789012', status: CouponStatus.sold);
    expect(c.sold, isTrue);
    expect(c.display, '1234 5678 9012');
    expect(const Coupon(number: 'AB12CD34', status: CouponStatus.pending).sold, isFalse);
  });

  test('스크린샷 줄이기: 큰 PNG 는 900KB 이하 JPEG 로, 작은 JPEG 는 그대로', () async {
    // 무늬가 있는 큰 이미지 (압축이 잘 안 되게)
    final big = img.Image(width: 1600, height: 3200);
    var seed = 12345;
    int rnd() {
      seed = (seed * 1103515245 + 12345) & 0x7fffffff;
      return (seed >> 16) & 0xff;
    }
    for (var y = 0; y < big.height; y++) {
      for (var x = 0; x < big.width; x++) {
        // 부드러운 그림 + 약한 잡음: PNG 는 크지만 JPEG 로는 잘 줄어드는, 실제 스크린샷에 가까운 이미지
        big.setPixelRgb(x, y, (x ~/ 8 + rnd() % 24) % 256, (y ~/ 16 + rnd() % 24) % 256, ((x + y) ~/ 24 + rnd() % 24) % 256);
      }
    }
    final png = Uint8List.fromList(img.encodePng(big));
    expect(png.length, greaterThan(couponImageMaxBytes));
    final out = await prepareCouponImage(png);
    expect(out, isNotNull);
    expect(out!.length, lessThanOrEqualTo(couponImageMaxBytes));
    expect(out[0], 0xff); // JPEG
    expect(out[1], 0xd8);
    final decoded = img.decodeJpg(out)!;
    expect(decoded.width, lessThanOrEqualTo(1280));
    // 이미 작은 JPEG 는 그대로
    final small = Uint8List.fromList(img.encodeJpg(img.Image(width: 100, height: 100), quality: 80));
    expect(identical(await prepareCouponImage(small), small), isTrue);
    // 이미지가 아니면 null
    expect(await prepareCouponImage(Uint8List.fromList(List.filled(2000, 7))), isNull);
  });

  testWidgets('기능 메뉴: 쿠폰 판매가 목록에 있다', (tester) async {
    expect(appFeatures.map((f) => f.id), contains('coupons'));
    await tester.pumpWidget(const MaterialApp(home: FeaturesScreen()));
    expect(find.text('기능'), findsOneWidget);
    expect(find.text('쿠폰 판매'), findsOneWidget);
  });
}
