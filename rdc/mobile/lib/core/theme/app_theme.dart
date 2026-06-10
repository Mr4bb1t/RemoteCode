/// RDC — Tema e Design System
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class RdcTheme {
  RdcTheme._();

  // ── Paleta de cores ───────────────────────────────────────────────────────
  static const Color primary = Color(0xFF6C63FF);      // Violeta principal
  static const Color primaryDark = Color(0xFF4D44E8);
  static const Color accent = Color(0xFF00D4AA);        // Verde-água acento
  static const Color danger = Color(0xFFFF5C6A);        // Erro / perigo
  static const Color warning = Color(0xFFFFB347);       // Aviso
  static const Color success = Color(0xFF4ADE80);       // Sucesso
  static const Color info = Color(0xFF38BDF8);          // Info

  // Dark background layers
  static const Color bg900 = Color(0xFF0D0D14);   // Fundo mais profundo
  static const Color bg800 = Color(0xFF13131E);   // Fundo principal
  static const Color bg700 = Color(0xFF1A1A28);   // Cards
  static const Color bg600 = Color(0xFF22223A);   // Inputs, surface elevado
  static const Color bg500 = Color(0xFF2E2E4A);   // Borders, dividers

  // Texto
  static const Color textPrimary = Color(0xFFF0F0FF);
  static const Color textSecondary = Color(0xFFAAAAAD);
  static const Color textMuted = Color(0xFF6B6B80);

  // ── Gradientes ────────────────────────────────────────────────────────────
  static const LinearGradient primaryGradient = LinearGradient(
    colors: [primary, Color(0xFF8B5CF6)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient accentGradient = LinearGradient(
    colors: [accent, Color(0xFF00A896)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient cardGradient = LinearGradient(
    colors: [bg700, bg600],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  // ── ThemeData ─────────────────────────────────────────────────────────────
  static ThemeData get darkTheme {
    final base = ThemeData.dark();
    final textTheme = GoogleFonts.interTextTheme(base.textTheme).apply(
      bodyColor: textPrimary,
      displayColor: textPrimary,
    );

    return base.copyWith(
      useMaterial3: true,
      scaffoldBackgroundColor: bg800,
      colorScheme: const ColorScheme.dark(
        primary: primary,
        secondary: accent,
        error: danger,
        surface: bg700,
        surfaceVariant: bg600,
        background: bg800,
        onPrimary: Colors.white,
        onSecondary: Colors.white,
        onSurface: textPrimary,
        onBackground: textPrimary,
      ),
      textTheme: textTheme,
      appBarTheme: AppBarTheme(
        backgroundColor: bg800,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: GoogleFonts.inter(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: textPrimary,
        ),
        iconTheme: const IconThemeData(color: textPrimary),
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: bg900,
        selectedItemColor: primary,
        unselectedItemColor: textMuted,
        type: BottomNavigationBarType.fixed,
        elevation: 0,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: bg900,
        indicatorColor: primary.withOpacity(0.2),
        iconTheme: MaterialStateProperty.resolveWith((states) {
          if (states.contains(MaterialState.selected)) {
            return const IconThemeData(color: primary);
          }
          return const IconThemeData(color: textMuted);
        }),
        labelTextStyle: MaterialStateProperty.resolveWith((states) {
          if (states.contains(MaterialState.selected)) {
            return GoogleFonts.inter(fontSize: 12, color: primary, fontWeight: FontWeight.w600);
          }
          return GoogleFonts.inter(fontSize: 12, color: textMuted);
        }),
      ),
      cardTheme: CardThemeData(
        color: bg700,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: bg500, width: 1),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: bg600,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: bg500),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: bg500),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: primary, width: 2),
        ),
        labelStyle: const TextStyle(color: textSecondary),
        hintStyle: const TextStyle(color: textMuted),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          textStyle: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 15),
          elevation: 0,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: primary,
          side: const BorderSide(color: primary),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: bg600,
        selectedColor: primary.withOpacity(0.2),
        labelStyle: const TextStyle(color: textPrimary, fontSize: 12),
        side: BorderSide(color: bg500),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      dividerTheme: const DividerThemeData(
        color: bg500,
        thickness: 1,
        space: 1,
      ),
      iconTheme: const IconThemeData(color: textSecondary),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: bg600,
          borderRadius: BorderRadius.circular(8),
        ),
        textStyle: const TextStyle(color: textPrimary),
      ),
    );
  }
}
