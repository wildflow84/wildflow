import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';

import 'data/push.dart';
import 'data/repository.dart';
import 'data/store.dart';
import 'firebase_options.dart';
import 'ui/home_screen.dart';
import 'ui/login_screen.dart';
import 'ui/space_screen.dart';
import 'ui/palette.dart';
import 'ui/splash.dart';

/// 앱이 열려 있는 동안 받은 푸시를 스낵바로 보여주기 위한 키
final messengerKey = GlobalKey<ScaffoldMessengerState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('ko');
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  Push.listenForeground(messengerKey);
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
      scaffoldMessengerKey: messengerKey,
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
        fontFamily: 'Pretendard',
        brightness: Brightness.light,
        colorScheme: ColorScheme.fromSeed(seedColor: kAccent).copyWith(
          primary: kAccent,
          onPrimary: Colors.white,
          primaryContainer: const Color(0xFFFBE3CC),
          onPrimaryContainer: const Color(0xFF8A4A14),
          secondaryContainer: const Color(0xFFFBE3CC),
          onSecondaryContainer: const Color(0xFF8A4A14),
          surface: kBg,
          onSurface: kInk,
          onSurfaceVariant: kSubtle,
          surfaceContainerLowest: kCard,
          surfaceContainerLow: kBg,
          surfaceContainer: const Color(0xFFF7EFE1),
          surfaceContainerHigh: const Color(0xFFF4EBDC),
          surfaceContainerHighest: const Color(0xFFF0E5D3),
          outline: kFaint,
          outlineVariant: kLine,
          error: kRed,
        ),
        scaffoldBackgroundColor: kBg,
        dividerColor: kLine,
        // 모든 화면의 상단 바를 같은 배경으로
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.transparent,
          foregroundColor: kInk,
          scrolledUnderElevation: 0,
          surfaceTintColor: Colors.transparent,
        ),
        navigationBarTheme: const NavigationBarThemeData(
          backgroundColor: kCard,
          surfaceTintColor: Colors.transparent,
          indicatorColor: Color(0xFFFBE3CC),
        ),
        floatingActionButtonTheme: FloatingActionButtonThemeData(
          backgroundColor: kAccent,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        ),
        cardTheme: CardThemeData(
          color: kCard,
          elevation: 1,
          shadowColor: kCardShadow,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        ),
        dialogTheme: DialogThemeData(
          backgroundColor: kCard,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        ),
        bottomSheetTheme: const BottomSheetThemeData(
          backgroundColor: kBg,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
        ),
        chipTheme: ChipThemeData(
          backgroundColor: kCard,
          side: const BorderSide(color: kLine),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(99)),
          selectedColor: const Color(0xFFFBE3CC),
        ),
        popupMenuTheme: const PopupMenuThemeData(color: kCard, surfaceTintColor: Colors.transparent),
        // 모든 입력창을 같은 외곽선 스타일로
        inputDecorationTheme: InputDecorationTheme(
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: kFaint)),
          filled: true,
          fillColor: kCard,
        ),
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
      return const SplashView();
    }
    if (s.user == null) return const LoginScreen();
    if (s.spaceId == null) return const SpaceScreen();
    return const HomeScreen();
  }
}
