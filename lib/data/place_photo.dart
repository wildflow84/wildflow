import 'dart:convert';

import 'package:http/http.dart' as http;

/// 위치 문구에서 사진 검색에 쓸 이름만 뽑는다. ("도쿄 · 일본 도쿄도" → "도쿄")
String photoQueryOf(String location) {
  var q = location.split(' · ').first.trim();
  q = q.replaceAll(RegExp(r'\s+'), ' ');
  return q;
}

/// 위키백과 검색 응답에서 대표 이미지를 고른다. 제목이 검색어와 겹치는 문서만 쓴다.
String? pickPhotoUrl(Map<String, dynamic> json, String query) {
  final pages = (json['query']?['pages'] as Map?)?.values.toList() ?? const [];
  final sorted = pages.map((e) => Map<String, dynamic>.from(e as Map)).toList()
    ..sort((a, b) => ((a['index'] ?? 99) as num).compareTo((b['index'] ?? 99) as num));
  final q = query.toLowerCase().replaceAll(' ', '');
  for (final p in sorted) {
    final url = p['thumbnail']?['source'];
    if (url is! String) continue;
    final t = '${p['title'] ?? ''}'.toLowerCase().replaceAll(' ', '');
    if (t.isEmpty || q.isEmpty) continue;
    if (t.contains(q) || q.contains(t)) return url;
  }
  return null;
}

/// 장소 이름으로 사진을 찾는다 (위키백과 한국어 → 영어). 유명한 도시/명소/공항 위주로 찾아지고,
/// 일반 상점은 보통 사진이 없다. 못 찾으면 null.
Future<String?> fetchPlacePhoto(String location) async {
  final q = photoQueryOf(location);
  if (q.length < 2) return null;
  for (final lang in const ['ko', 'en']) {
    try {
      final uri = Uri.https('$lang.wikipedia.org', '/w/api.php', {
        'action': 'query',
        'generator': 'search',
        'gsrsearch': q,
        'gsrlimit': '5',
        'prop': 'pageimages',
        'piprop': 'thumbnail',
        'pithumbsize': '640',
        'format': 'json',
        'origin': '*',
      });
      final r = await http.get(uri).timeout(const Duration(seconds: 6));
      if (r.statusCode != 200) continue;
      final url = pickPhotoUrl(jsonDecode(r.body) as Map<String, dynamic>, q);
      if (url != null) return url;
    } catch (_) {}
  }
  return null;
}
