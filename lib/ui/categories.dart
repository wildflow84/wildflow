import 'package:flutter/material.dart';

class Category {
  final String id, label;
  final Color color;
  const Category(this.id, this.label, this.color);
}

const categories = <Category>[
  Category('default', '일반', Color(0xFF6C74D8)),
  Category('work', '업무', Color(0xFFE8794B)),
  Category('family', '가족', Color(0xFF8DB04A)),
  Category('money', '재테크', Color(0xFFE3B341)),
  Category('travel', '여행', Color(0xFF3FA796)),
  Category('kid', '대희', Color(0xFFD06A9E)),
];

Category categoryOf(String id) =>
    categories.firstWhere((c) => c.id == id, orElse: () => categories.first);
