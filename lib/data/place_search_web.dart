import 'dart:js_interop';

const supported = true;

@JS('ourdayKakaoSearch')
external JSPromise<JSString> _search(JSString key, JSString query);

/// web/index.html 의 ourdayKakaoSearch (카카오 지도 JS SDK의 장소 검색)를 호출한다.
/// REST API는 브라우저에서 CORS로 막혀서 JS SDK를 쓴다.
Future<String> kakaoKeywordSearch(String key, String query) async =>
    (await _search(key.toJS, query.toJS).toDart).toDart;
