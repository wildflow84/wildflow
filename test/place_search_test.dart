import 'package:flutter_test/flutter_test.dart';
import 'package:ourday/data/place_search.dart';

void main() {
  test('카카오 키워드 검색 응답 파싱: x=경도, y=위도, 도로명 주소 우선', () {
    const json = '''[
      {"place_name":"스타벅스 오산세교점","address_name":"경기 오산시 세교동 1","road_address_name":"경기 오산시 세교로 1","x":"127.0716","y":"37.1632"},
      {"place_name":"이름만","address_name":"경기 어딘가","road_address_name":"","x":"127.0","y":"37.0"},
      {"place_name":"좌표없음","address_name":"x","road_address_name":"","x":"","y":""}
    ]''';
    final r = parseKakaoPlaces(json);
    expect(r.length, 2);
    expect(r[0].name, '스타벅스 오산세교점');
    expect(r[0].lat, 37.1632);
    expect(r[0].lng, 127.0716);
    expect(r[0].label, '스타벅스 오산세교점 · 경기 오산시 세교로 1');
    expect(r[1].address, '경기 어딘가');
  });

  test('키가 없으면 검색을 막는다', () async {
    expect(placeSearchAvailable, false);
    expect(await searchPlaces('오산'), isEmpty);
  });
}
