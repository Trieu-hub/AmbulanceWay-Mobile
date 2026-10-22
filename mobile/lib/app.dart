import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';

import 'models/session.dart';
import 'screens/driver/driver_shell.dart';
import 'screens/patient/patient_shell.dart';
import 'screens/welcome_screen.dart';
import 'services/notification_service.dart';
import 'state/app_state.dart';

/// Màu chủ đạo, trùng màu đỏ của bản web.
const Color kBrandRed = Color(0xFFD32F2F);

class AmbulanceWayApp extends StatelessWidget {
  const AmbulanceWayApp({super.key, this.appState, this.notifier = const NoopNotifier()});

  /// Cho phép test truyền sẵn trạng thái; bình thường app tự tạo và đọc dữ liệu đã lưu.
  final AppState? appState;

  /// Thông báo hệ thống khi app chạy nền (main() truyền bản thật, test dùng bản rỗng).
  final AppNotifier notifier;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider<AppNotifier>.value(value: notifier),
        ChangeNotifierProvider<AppState>(create: (_) => appState ?? (AppState()..load())),
      ],
      child: MaterialApp(
        title: 'AmbulanceWay',
        debugShowCheckedModeBanner: false,
        theme: buildAppTheme(),
        locale: const Locale('vi'),
        supportedLocales: const [Locale('vi'), Locale('en')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        // Trên màn hình rộng (trình duyệt, máy tính) giữ bề ngang như điện thoại.
        builder: (context, child) => ColoredBox(
          color: const Color(0xFF263238),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: ClipRect(child: child),
            ),
          ),
        ),
        home: const AppGate(),
      ),
    );
  }
}

ThemeData buildAppTheme() {
  final scheme = ColorScheme.fromSeed(seedColor: kBrandRed, primary: kBrandRed);
  final rounded = RoundedRectangleBorder(borderRadius: BorderRadius.circular(14));
  return ThemeData(
    colorScheme: scheme,
    scaffoldBackgroundColor: const Color(0xFFF7F7F9),
    // Mọi nền tảng dùng cùng kiểu chuyển màn hình trượt ngang.
    pageTransitionsTheme: PageTransitionsTheme(builders: {
      for (final platform in TargetPlatform.values)
        platform: const CupertinoPageTransitionsBuilder(),
    }),
    appBarTheme: const AppBarTheme(
      backgroundColor: kBrandRed,
      foregroundColor: Colors.white,
      centerTitle: true,
      elevation: 0,
      scrolledUnderElevation: 0,
      titleTextStyle: TextStyle(color: Colors.white, fontSize: 19, fontWeight: FontWeight.w700),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: Colors.white,
      elevation: 8,
      indicatorColor: kBrandRed.withValues(alpha: 0.14),
      labelTextStyle: WidgetStateProperty.resolveWith((states) => TextStyle(
            fontSize: 12,
            fontWeight: states.contains(WidgetState.selected) ? FontWeight.w700 : FontWeight.w500,
          )),
    ),
    chipTheme: ChipThemeData(
      shape: const StadiumBorder(),
      side: BorderSide(color: Colors.grey.shade300),
      selectedColor: kBrandRed.withValues(alpha: 0.14),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(0, 52),
        shape: rounded,
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 48),
        shape: rounded,
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
      ),
    ),
    cardTheme: CardThemeData(
      color: Colors.white,
      elevation: 1,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
  );
}

/// Chọn màn hình gốc theo phiên đăng nhập: chào mừng, tài xế hoặc bệnh nhân.
class AppGate extends StatefulWidget {
  const AppGate({super.key});

  @override
  State<AppGate> createState() => _AppGateState();
}

class _AppGateState extends State<AppGate> {
  UserRole? _shownRole;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    if (!app.ready) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final session = app.session;
    if (session?.role != _shownRole) {
      _shownRole = session?.role;
      // Vừa đăng nhập hoặc đăng xuất: đóng các màn hình đang mở chồng lên (form đăng nhập, hồ sơ...).
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).popUntil((route) => route.isFirst);
      });
    }

    if (session == null) return const WelcomeScreen();
    switch (session.role) {
      case UserRole.driver:
        return DriverShell(key: ValueKey('driver-${session.token}'));
      case UserRole.patient:
        return PatientShell(key: ValueKey('patient-${session.token}'));
    }
  }
}
