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
  final Widget home;
  const OurDayApp({super.key, this.home = const _Gate()});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '순대희 캘린더',
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
        // 모든 화면의 상단 바를 같은 배경으로
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.transparent,
          scrolledUnderElevation: 0,
          surfaceTintColor: Colors.transparent,
        ),
        // 모든 입력창을 같은 외곽선 스타일로
        inputDecorationTheme: const InputDecorationTheme(border: OutlineInputBorder()),
        snackBarTheme: SnackBarThemeData(
          behavior: SnackBarBehavior.floating,
          insetPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
      home: home,
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
