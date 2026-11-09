import 'package:flutter/material.dart';

class AppColors {
  AppColors._();

  static const purple = Color(0xFF7B5CFF);
  static const purpleSoft = Color(0xFFF0EBFF);
  static const red = Color(0xFFE53935);
  static const redDeep = Color(0xFFC62828);
  static const green = Color(0xFF2E7D32);
  static const blue = Color(0xFF1E88E5);
  static const navBlue = Color(0xFF2F6BFF);
  static const orange = Color(0xFFF59E0B);
  static const late = Color(0xFFE67E22);
  static const textPrimary = Color(0xFF1A1A1A);
  static const textSecondary = Color(0xFF6B7280);
  static const scaffold = Color(0xFFF7F8FA);
  static const card = Colors.white;
}

ThemeData buildAppTheme() {
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: AppColors.purple,
      brightness: Brightness.light,
    ),
    scaffoldBackgroundColor: AppColors.scaffold,
    fontFamily: 'Roboto',
  );

  return base.copyWith(
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.scaffold,
      elevation: 0,
      foregroundColor: AppColors.textPrimary,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: Colors.grey.shade300),
      ),
    ),
  );
}
