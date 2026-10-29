import 'package:cloud_firestore/cloud_firestore.dart';

/// 쿠폰 판매 기능의 쿠폰 한 장. 문서 id 가 곧 정규화된 번호라서 같은 번호는 한 번만 등록된다.
/// 쓰기는 서버 함수만 한다 (앱은 읽기만).
class Coupon {
  final String number; // 정규화된 번호 (대문자 영문/숫자)
  final CouponStatus status;
  final String requestedByName;
  final DateTime? requestedAt;
  final DateTime? soldAt;
  final String itemId; // 판매 할 일 항목 id

  const Coupon({
    required this.number,
    required this.status,
    this.requestedByName = '',
    this.requestedAt,
    this.soldAt,
    this.itemId = '',
  });

  factory Coupon.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final m = doc.data() ?? const <String, dynamic>{};
    return Coupon(
      number: doc.id,
      status: m['status'] == 'sold' ? CouponStatus.sold : CouponStatus.pending,
      requestedByName: (m['requestedByName'] as String?) ?? '',
      requestedAt: (m['requestedAt'] as Timestamp?)?.toDate(),
      soldAt: (m['soldAt'] as Timestamp?)?.toDate(),
      itemId: (m['itemId'] as String?) ?? '',
    );
  }

  bool get sold => status == CouponStatus.sold;

  /// 화면에 보일 번호 (숫자만이면 4자리씩 끊는다)
  String get display => formatCouponNumber(number);
}

enum CouponStatus { pending, sold }

/// 스크린샷에서 읽은 번호 후보. [ocr]: ok / empty(번호를 못 찾음) / unavailable(글자 읽기 기능이 꺼져 있음) / error
class CouponScan {
  final List<String> candidates;
  final String ocr;
  const CouponScan(this.candidates, this.ocr);
}

/// 이미 있는 쿠폰이라 등록할 수 없을 때. [sold] 가 true 면 이미 판매한 쿠폰, false 면 판매 대기 중.
class CouponAlreadyException implements Exception {
  final bool sold;
  final String message;
  const CouponAlreadyException({required this.sold, this.message = ''});
  @override
  String toString() => message;
}

/// 서버(functions/coupon.js)와 같은 규칙: 대문자, 공백/하이픈/점/밑줄 제거, 영문/숫자 6~32자. 아니면 null.
String? normalizeCouponNumber(String input) {
  final v = input.toUpperCase().replaceAll(RegExp(r'[\s\-_.·]'), '');
  return RegExp(r'^[A-Z0-9]{6,32}$').hasMatch(v) ? v : null;
}

/// 숫자만이면 4자리씩 끊어서 보여 준다 ("123456789012" -> "1234 5678 9012")
String formatCouponNumber(String n) =>
    RegExp(r'^\d+$').hasMatch(n) ? n.replaceAllMapped(RegExp(r'(\d{4})(?=\d)'), (m) => '${m[1]} ') : n;
