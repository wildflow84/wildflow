import 'package:flutter/material.dart';

import '../ui/palette.dart';
import 'feature_registry.dart';

/// "기능" 메뉴: 달력 말고 우리 둘이 쓰려고 붙인 기능들의 모음.
class FeaturesScreen extends StatelessWidget {
  const FeaturesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('기능')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          for (final f in appFeatures)
            Card(
              child: ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                leading: CircleAvatar(backgroundColor: kAccentSoft, foregroundColor: kAccentDeep, child: Icon(f.icon)),
                title: Text(f.title, style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text(f.subtitle),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: f.builder)),
              ),
            ),
          const SizedBox(height: 8),
          Center(child: Text('앞으로 붙이는 기능은 여기에 모여', style: TextStyle(color: kMuted, fontSize: 12))),
        ],
      ),
    );
  }
}
