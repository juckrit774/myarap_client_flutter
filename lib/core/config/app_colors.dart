import 'package:flutter/material.dart';

class AppColors {
  AppColors._();

  static const deepPurple = Color(0xFF42286F);
  static const mainPurple = Color(0xFF745895);
  static const opaPurple = Color(0xFF8585FD);
  static const bgColor = Color(0xFFF6F6F6);
  static const orange = Color(0xFFFBAC53);

  static const headerGradient = LinearGradient(
    colors: [deepPurple, mainPurple],
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
  );
}
