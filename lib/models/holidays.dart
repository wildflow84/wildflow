/// 양력 고정 공휴일/기념일. 음력 공휴일(설날, 부처님오신날, 추석)은 아직 미지원.
const _fixed = <String, String>{
  '01-01': '신정',
  '03-01': '삼일절',
  '05-05': '어린이날',
  '06-06': '현충일',
  '08-15': '광복절',
  '10-01': '국군의날',
  '10-03': '개천절',
  '10-09': '한글날',
  '12-25': '성탄절',
};

String? holidayName(DateTime d) {
  final k = '${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  return _fixed[k];
}
