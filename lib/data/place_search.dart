import 'dart:convert';

import 'place_search_stub.dart' if (dart.library.js_interop) 'place_search_web.dart' as impl;

/// 장소 검색 결과. 국내는 카카오 로컬, 해외는 구글 Places(추후)로 찾는다.
class Place {
  final String name;
  final String address;
  final double lat;
  final double lng;
  final bool overseas;
  const Place({required this.name, required this.address, required this.lat, required this.lng, this.overseas = false});

  /// 위치 칸에 저장할 문구: 이름 + 주소
  String get label => address.isEmpty || address == name ? name : '$name · $address';
}

/// 카카오 JavaScript 키 (공개 값, 카카오 개발자 콘솔에서 사이트 도메인 제한). 비어 있으면 장소 검색을 숨긴다.
const kakaoJsKey = String.fromEnvironment('KAKAO_JS_KEY');

bool get placeSearchAvailable => kakaoJsKey.isNotEmpty && impl.supported;

/// 카카오 키워드 검색 응답(JSON 배열)을 [Place] 목록으로. x=경도, y=위도.
List<Place> parseKakaoPlaces(String json) {
  final list = jsonDecode(json) as List;
  final out = <Place>[];
  for (final e in list) {
    final m = e as Map;
    final lat = double.tryParse('${m['y']}');
    final lng = double.tryParse('${m['x']}');
    if (lat == null || lng == null) continue;
    final road = '${m['road_address_name'] ?? ''}';
    out.add(Place(
      name: '${m['place_name'] ?? ''}',
      address: road.isNotEmpty ? road : '${m['address_name'] ?? ''}',
      lat: lat,
      lng: lng,
    ));
  }
  return out;
}

Future<List<Place>> searchPlaces(String query) async {
  final q = query.trim();
  if (q.length < 2 || !placeSearchAvailable) return const [];
  final json = await impl.kakaoKeywordSearch(kakaoJsKey, q);
  return parseKakaoPlaces(json);
}
