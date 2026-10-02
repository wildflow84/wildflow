import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';

import 'data/repository.dart';
import 'data/store.dart';
import 'firebase_options.dart';
import 'ui/home_screen.dart';
import 'ui/login_screen.dart';
import 'ui/space_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('ko');
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  runApp(ChangeNotifierProvider(
    create: (_) => Store(Repository()),
    child: const OurDayApp(),
  ));
}

class OurDayApp extends StatelessWidget {
  const OurDayApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'OurDay',
      debugShowCheckedModeBanner: false,
      locale: const Locale('ko'),
      supportedLocales: const [Locale('ko')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorSchemeSeed: const Color(0xFF4C6EF5),
        scaffoldBackgroundColor: const Color(0xFF1E2233),
      ),
      home: const _Gate(),
    );
  }
}

/// 로그인 → 공간(부부 공유 스페이스) 설정 → 홈 순서로 분기.
class _Gate extends StatelessWidget {
  const _Gate();

  @override
  Widget build(BuildContext context) {
    final s = context.watch<Store>();
    if (s.loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (s.user == null) return const LoginScreen();
    if (s.spaceId == null) return const SpaceScreen();
    return const HomeScreen();
  }
}
