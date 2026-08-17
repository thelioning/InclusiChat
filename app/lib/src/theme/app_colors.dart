import 'package:flutter/material.dart';

abstract final class AppColors {
  static const background = Color(0xFF14181B);
  static const surface = Color(0xFF1D2329);
  static const surfaceRaised = Color(0xFF262D34);
  static const primary = Color(0xFFCD1AE9);
  static const secondary = Color(0xFF7624C9);
  static const receiptRead = Color(0xFFBE7AFF);
  static const textPrimary = Color(0xFFFFFFFF);
  static const textSecondary = Color(0xFFB7BEC7);
  static const success = Color(0xFF27C982);
  static const warning = Color(0xFFF4B740);
  static const error = Color(0xFFEF5350);

  static const brandGradient = LinearGradient(
    colors: [secondary, primary],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}
