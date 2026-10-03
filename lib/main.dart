import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';
import 'package:home_widget/home_widget.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';

import 'data/location_report.dart';
import 'data/push.dart';
import 'data/widget_actions.dart';
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
  if (!kIsWeb) {
    // 홈 화면 위젯의 체크박스(앱을 열지 않고 완료 처리)
    HomeWidget.registerInteractivityCallback(widgetBackgroundCallback);
  }
  final store = Store(Repository());
  LocationReporter(store).start(); // 출발 시간 알림용 위치 전달
  runApp(ChangeNotifierProvider.value(
    value: store,
    child: const OurDayApp(),
  ));
}

/// 화면 테마 설정: system(기기 설정 따라감) / light / dark
bool resolveDark(String mode, Brightness platform) =>
    mode == 'dark' || (mode == 'system' && platform == Brightness.dark);

ThemeData buildTheme(bool dark) => ThemeData(
        useMaterial3: true,
        fontFamily: 'Pretendard',
        brightness: dark ? Brightness.dark : Brightness.light,
        colorScheme: ColorScheme.fromSeed(seedColor: kAccent, brightness: dark ? Brightness.dark : Brightness.light).copyWith(
          primary: kAccent,
          onPrimary: dark ? const Color(0xFF2A1708) : Colors.white,
          primaryContainer: kAccentSoft,
          onPrimaryContainer: kAccentDeep,
          secondaryContainer: kAccentSoft,
          onSecondaryContainer: kAccentDeep,
          surface: kBg,
          onSurface: kInk,
          onSurfaceVariant: kSubtle,
          surfaceContainerLowest: kCard,
          surfaceContainerLow: kBg,
          surfaceContainer: dark ? const Color(0xFF1B1E26) : const Color(0xFFF7EFE1),
          surfaceContainerHigh: kFill,
          surfaceContainerHighest: dark ? const Color(0xFF2E333D) : const Color(0xFFF0E5D3),
          outline: kFaint,
          outlineVariant: kLine,
          error: kRed,
        ),
        scaffoldBackgroundColor: kBg,
        dividerColor: kLine,
        // 모든 화면의 상단 바를 같은 배경으로
        appBarTheme: AppBarTheme(
          backgroundColor: Colors.transparent,
          foregroundColor: kInk,
          systemOverlayStyle: SystemUiOverlayStyle(
            statusBarColor: Colors.transparent,
            statusBarIconBrightness: dark ? Brightness.light : Brightness.dark,
            statusBarBrightness: dark ? Brightness.dark : Brightness.light,
            systemNavigationBarColor: kBg,
            systemNavigationBarIconBrightness: dark ? Brightness.light : Brightness.dark,
          ),
          scrolledUnderElevation: 0,
          surfaceTintColor: Colors.transparent,
        ),
        navigationBarTheme: NavigationBarThemeData(
          backgroundColor: kCard,
          surfaceTintColor: Colors.transparent,
          indicatorColor: kAccentSoft,
        ),
        floatingActionButtonTheme: FloatingActionButtonThemeData(
          backgroundColor: kAccent,
          foregroundColor: dark ? const Color(0xFF2A1708) : Colors.white,
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
        bottomSheetTheme: BottomSheetThemeData(
          backgroundColor: kBg,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
        ),
        chipTheme: ChipThemeData(
          backgroundColor: kCard,
          side: BorderSide(color: kLine),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(99)),
          selectedColor: kAccentSoft,
        ),
        popupMenuTheme: PopupMenuThemeData(color: kCard, surfaceTintColor: Colors.transparent),
        // 모든 입력창을 같은 외곽선 스타일로
        inputDecorationTheme: InputDecorationTheme(
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: kFaint)),
          filled: true,
          fillColor: kCard,
        ),
        snackBarTheme: SnackBarThemeData(
          behavior: SnackBarBehavior.floating,
          insetPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );

class OurDayApp extends StatefulWidget {
  final Widget home;
  const OurDayApp({super.key, this.home = const _Gate()});

  @override
  State<OurDayApp> createState() => _OurDayAppState();
}

class _OurDayAppState extends State<OurDayApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // 기기의 어두운 모드가 바뀌면 "시스템" 설정일 때 따라간다
  @override
  void didChangePlatformBrightness() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final mode = context.select<Store, String>((s) => s.themeMode);
    final dark = resolveDark(mode, WidgetsBinding.instance.platformDispatcher.platformBrightness);
    applyPalette(dark); // 이 아래 모든 화면의 k색이 이 값을 따른다
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: dark ? Brightness.light : Brightness.dark,
      statusBarBrightness: dark ? Brightness.dark : Brightness.light,
      systemNavigationBarColor: kBg,
      systemNavigationBarIconBrightness: dark ? Brightness.light : Brightness.dark,
    ));
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
      theme: buildTheme(dark),
      // 테마가 바뀌면 화면 전체를 새로 그려서 모든 색이 바뀌게 한다
      builder: (context, child) => KeyedSubtree(key: ValueKey(dark), child: child ?? const SizedBox.shrink()),
      home: widget.home,
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
