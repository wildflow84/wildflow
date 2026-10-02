import 'package:flutter_test/flutter_test.dart';
import 'package:ourday/data/place_photo.dart';

void main() {
  test('위치 문구에서 검색어만 뽑기', () {
    expect(photoQueryOf('도쿄 · 일본 도쿄도'), '도쿄');
    expect(photoQueryOf('  제주   국제공항 '), '제주 국제공항');
  });

  test('위키백과 응답: 제목이 겹치는 이미지만 고른다', () {
    final json = {
      'query': {
        'pages': {
          '1': {'index': 2, 'title': '도쿄 타워', 'thumbnail': {'source': 'https://x/tower.jpg'}},
          '2': {'index': 1, 'title': '도쿄', 'thumbnail': {'source': 'https://x/tokyo.jpg'}},
          '3': {'index': 3, 'title': '엉뚱한 문서', 'thumbnail': {'source': 'https://x/other.jpg'}},
        }
      }
    };
    expect(pickPhotoUrl(json, '도쿄'), 'https://x/tokyo.jpg');
    expect(pickPhotoUrl(json, '오사카'), isNull);
    expect(pickPhotoUrl({'query': {'pages': {'1': {'index': 1, 'title': '도쿄'}}}}, '도쿄'), isNull);
    expect(pickPhotoUrl({}, '도쿄'), isNull);
  });
}
