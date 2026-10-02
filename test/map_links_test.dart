import 'package:flutter_test/flutter_test.dart';
import 'package:ourday/models/item.dart';
import 'package:ourday/models/map_links.dart';

void main() {
  test('지도 주소: 한글/공백이 안전하게 인코딩된다', () {
    final naver = mapUri(MapApp.naver, '판교역 스타벅스');
    expect(naver.host, 'map.naver.com');
    expect(naver.toString(), contains('%ED%8C%90%EA%B5%90'));
    final google = mapUri(MapApp.google, ' 오키나와 나하공항 ');
    expect(google.queryParameters['query'], '오키나와 나하공항');
    expect(google.queryParameters['api'], '1');
    expect(mapUri(MapApp.kakao, '세교 데시앙포레').queryParameters['q'], '세교 데시앙포레');
  });

  test('Item 위치 저장 / 기본값', () {
    final i = Item(id: 'x', type: ItemType.event, title: 't', start: DateTime(2026, 10, 2), ownerUid: 'me');
    expect(i.location, '');
    expect(i.copyWith(location: '나하공항').toMap()['location'], '나하공항');
  });
}
