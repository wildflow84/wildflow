import 'solar_term_table.g.dart';

/// 24절기. 날짜는 한국 표준시 기준이며 태양 황경을 정밀 계산해 만든 표를 쓴다. (1900~2200)
const solarTermNames = [
  '소한', '대한', '입춘', '우수', '경칩', '춘분', '청명', '곡우', '입하', '소만', '망종', '하지',
  '소서', '대서', '입추', '처서', '백로', '추분', '한로', '상강', '입동', '소설', '대설', '동지',
];

bool hasSolarTerms(int year) {
  final i = year - solarTermFirstYear;
  return i >= 0 && i < solarTermTable.length;
}

/// [year]년의 [index]번째 절기(0=소한 ... 23=동지) 날짜.
DateTime? solarTermDate(int year, int index) {
  if (!hasSolarTerms(year)) return null;
  return DateTime(year, 1, solarTermTable[year - solarTermFirstYear][index]);
}

/// [date]가 절기일이면 이름.
String? solarTermOn(DateTime date) {
  if (!hasSolarTerms(date.year)) return null;
  final yday = DateTime.utc(date.year, date.month, date.day)
          .difference(DateTime.utc(date.year, 1, 1))
          .inDays +
      1;
  final row = solarTermTable[date.year - solarTermFirstYear];
  final i = row.indexOf(yday);
  return i < 0 ? null : solarTermNames[i];
}
