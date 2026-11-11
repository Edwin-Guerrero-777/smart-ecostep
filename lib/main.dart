/// Punto de entrada de **Smart Eco-Step**.
///
/// Responsabilidades de este archivo:
/// 1. Inicializar Flutter y Firebase antes de dibujar la primera pantalla.
/// 2. Definir la paleta de colores global [AppColors] ("Ocean Blue Serenity").
/// 3. Construir el tema oscuro de toda la app ([SmartEcoStepApp]).
///
/// Flujo de pantallas:
/// ```
/// LoginScreen ──► HomeScreen (tablero DDR + gamificación)
///      │               ▲
///      └► RegisterScreen ┘
/// ```
library;

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:smart_ecostep/screens/login_screen.dart';
import 'firebase_options.dart';

/// Paleta "Ocean Blue Serenity": fondos azul noche y acentos cyan neón.
///
/// Todas las pantallas deben tomar sus colores de aquí para mantener
/// una estética coherente. No se puede instanciar (constructor privado).
class AppColors {
  AppColors._();

  /// Fondo principal: azul noche casi negro
  static const Color background = Color(0xFF070B19);

  /// Superficie de tarjetas y AppBar
  static const Color surface = Color(0xFF111827);

  /// Tarjetas elevadas / contenedores secundarios
  static const Color cardElevated = Color(0xFF1A2235);

  /// Borde sutil de tarjetas
  static const Color cardBorder = Color(0xFF1E3A5F);

  /// Acento principal — cyan neón brillante
  static const Color cyan = Color(0xFF00E5FF);

  /// Acento secundario — cyan más suave
  static const Color cyanSoft = Color(0xFF00B4D8);

  /// Acento terciario — azul hielo
  static const Color iceBlue = Color(0xFF48CAE4);

  /// Texto principal blanco
  static const Color textPrimary = Color(0xFFE8F4FD);

  /// Texto secundario gris claro
  static const Color textSecondary = Color(0xFF8BAABF);

  /// Error / alerta
  static const Color error = Color(0xFFFF5370);

  /// Éxito (verde neón)
  static const Color success = Color(0xFF00E676);

  /// Advertencia (ámbar)
  static const Color warning = Color(0xFFFFAB40);
}

/// Arranca la aplicación.
///
/// `ensureInitialized()` es obligatorio porque Firebase usa canales
/// nativos antes de que se ejecute `runApp`.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Statusbar transparente para inmersión total con el fondo oscuro
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
    ),
  );

  // Configuración generada por `flutterfire configure` (firebase_options.dart)
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  runApp(const SmartEcoStepApp());
}

/// Widget raíz: configura el [MaterialApp] con el tema oscuro y
/// abre siempre en [LoginScreen].
class SmartEcoStepApp extends StatelessWidget {
  const SmartEcoStepApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Smart Eco-Step',
      debugShowCheckedModeBanner: false,
      theme: _buildDarkTheme(),
      home: const LoginScreen(),
    );
  }

  /// Tema Material 3 oscuro basado en [AppColors].
  ///
  /// Define el estilo por defecto de AppBar, tarjetas, campos de texto,
  /// botones, SnackBars y tipografía, para que las pantallas no tengan
  /// que repetir estilos.
  ThemeData _buildDarkTheme() {
    const cyan = AppColors.cyan;
    const bg = AppColors.background;
    const surface = AppColors.surface;

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,

      // ── ColorScheme totalmente personalizado ──────────────────────────────
      colorScheme: const ColorScheme.dark(
        brightness: Brightness.dark,
        primary: AppColors.cyan,
        onPrimary: AppColors.background,
        primaryContainer: AppColors.cardElevated,
        onPrimaryContainer: AppColors.cyan,
        secondary: AppColors.cyanSoft,
        onSecondary: AppColors.background,
        secondaryContainer: Color(0xFF0D2137),
        onSecondaryContainer: AppColors.textPrimary,
        tertiary: AppColors.iceBlue,
        onTertiary: AppColors.background,
        surface: AppColors.surface,
        onSurface: AppColors.textPrimary,
        surfaceContainerHighest: AppColors.cardElevated,
        outline: AppColors.textSecondary,
        error: AppColors.error,
        onError: Colors.white,
      ),

      // ── Scaffold ──────────────────────────────────────────────────────────
      scaffoldBackgroundColor: bg,

      // ── AppBar ────────────────────────────────────────────────────────────
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: AppColors.textPrimary,
          fontSize: 18,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.5,
        ),
        iconTheme: IconThemeData(color: AppColors.cyan),
      ),

      // ── Card ──────────────────────────────────────────────────────────────
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: AppColors.cardBorder, width: 1),
        ),
        margin: EdgeInsets.zero,
      ),

      // ── InputDecoration ───────────────────────────────────────────────────
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.cardElevated,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
        labelStyle: const TextStyle(color: AppColors.textSecondary),
        hintStyle: const TextStyle(color: AppColors.textSecondary),
        prefixIconColor: AppColors.textSecondary,
        suffixIconColor: AppColors.textSecondary,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.cardBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.cardBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: cyan, width: 1.8),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.error),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.error, width: 1.8),
        ),
        errorStyle: const TextStyle(color: AppColors.error),
      ),

      // ── ElevatedButton ────────────────────────────────────────────────────
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: cyan,
          foregroundColor: AppColors.background,
          minimumSize: const Size.fromHeight(52),
          elevation: 0,
          shadowColor: cyan.withAlpha(80),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.5,
          ),
        ),
      ),

      // ── TextButton ────────────────────────────────────────────────────────
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: cyan),
      ),

      // ── Divider ───────────────────────────────────────────────────────────
      dividerTheme: const DividerThemeData(
        color: AppColors.cardBorder,
        thickness: 1,
      ),

      // ── SnackBar ──────────────────────────────────────────────────────────
      snackBarTheme: SnackBarThemeData(
        backgroundColor: AppColors.cardElevated,
        contentTextStyle: const TextStyle(color: AppColors.textPrimary),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        behavior: SnackBarBehavior.floating,
      ),

      // ── Typography ────────────────────────────────────────────────────────
      textTheme: const TextTheme(
        headlineLarge: TextStyle(
          color: AppColors.textPrimary,
          fontWeight: FontWeight.bold,
        ),
        headlineMedium: TextStyle(
          color: AppColors.textPrimary,
          fontWeight: FontWeight.bold,
        ),
        headlineSmall: TextStyle(
          color: AppColors.textPrimary,
          fontWeight: FontWeight.bold,
        ),
        titleLarge: TextStyle(
          color: AppColors.textPrimary,
          fontWeight: FontWeight.w600,
        ),
        titleMedium: TextStyle(
          color: AppColors.textPrimary,
          fontWeight: FontWeight.w600,
        ),
        bodyLarge: TextStyle(color: AppColors.textPrimary),
        bodyMedium: TextStyle(color: AppColors.textPrimary),
        bodySmall: TextStyle(color: AppColors.textSecondary),
        labelSmall: TextStyle(color: AppColors.textSecondary),
      ),
    );
  }
}
