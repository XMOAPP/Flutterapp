import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

const Color kBlack = Color(0xFF000000);
const Color kDarkGrey = Color(0xFF1A1A1A);
const Color kDarkerGrey = Color(0xFF111111);
const Color kMediumGrey = Color(0xFF2A2A2A);
const Color kLightGrey = Color(0xFF888888);
const Color kLimeGreen = Color(0xFFA3E635);
const Color kBlueGrey = Color(0xFF3A3A3C); // Message bubble grey for unread badges
const Color kWhite = Color(0xFFFFFFFF);

ThemeData buildXmoTheme() {
  return ThemeData(
    brightness: Brightness.dark,
    scaffoldBackgroundColor: kBlack,
    primaryColor: kLimeGreen,
    colorScheme: const ColorScheme.dark(
      primary: kLimeGreen,
      secondary: kLimeGreen,
      surface: kDarkGrey,
    ),
    textTheme: GoogleFonts.interTextTheme(
      ThemeData.dark().textTheme,
    ).copyWith(
      bodyLarge: GoogleFonts.inter(color: kWhite, fontSize: 16),
      bodyMedium: GoogleFonts.inter(color: kWhite, fontSize: 14),
      bodySmall: GoogleFonts.inter(color: kLightGrey, fontSize: 12),
      titleLarge: GoogleFonts.inter(
          color: kWhite, fontSize: 20, fontWeight: FontWeight.bold),
      titleMedium: GoogleFonts.inter(
          color: kWhite, fontSize: 16, fontWeight: FontWeight.w600),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: kBlack,
      elevation: 0,
      iconTheme: const IconThemeData(color: kWhite),
      titleTextStyle: GoogleFonts.inter(
        color: kWhite,
        fontSize: 22,
        fontWeight: FontWeight.bold,
      ),
    ),
    drawerTheme: const DrawerThemeData(
      backgroundColor: Color(0xFF0F0F0F),
    ),
    iconTheme: const IconThemeData(color: kWhite),
  );
}
