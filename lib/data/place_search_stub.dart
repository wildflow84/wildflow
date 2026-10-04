import 'dart:convert';

import 'package:cloud_functions/cloud_functions.dart';

/// 안드로이드 등 웹이 아닌 곳: 카카오 키를 앱에 넣지 않고, 서버 함수(searchPlaces)가 대신 검색한다.
const supported = true;
const needsKey = false;

Future<String> kakaoKeywordSearch(String key, String query) async {
  final r = await FirebaseFunctions.instanceFor(region: 'asia-northeast3')
      .httpsCallable('searchPlaces')
      .call<Map<Object?, Object?>>({'query': query});
  return jsonEncode(r.data['documents'] ?? const []);
}
