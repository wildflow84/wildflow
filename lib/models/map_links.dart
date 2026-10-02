enum MapApp { naver, google, kakao }

const mapAppNames = {
  MapApp.naver: '네이버 지도',
  MapApp.google: '구글 지도',
  MapApp.kakao: '카카오맵',
};

/// 위치 문자열로 지도 앱/웹의 검색 결과를 여는 주소. (API 키 불필요)
Uri mapUri(MapApp app, String place) {
  final q = place.trim();
  switch (app) {
    case MapApp.naver:
      return Uri.https('map.naver.com', '/p/search/$q');
    case MapApp.google:
      return Uri.https('www.google.com', '/maps/search/', {'api': '1', 'query': q});
    case MapApp.kakao:
      return Uri.https('map.kakao.com', '/', {'q': q});
  }
}
