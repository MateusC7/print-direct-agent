import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'app_colors.dart';

/// Estilos de texto basados en Inter, inspirados en Notion.
class AppTextStyles {
  AppTextStyles._();

  // ── Títulos ──────────────────────────────────────────────
  static TextStyle titleLarge(BuildContext context) => GoogleFonts.inter(
        fontSize: 20,
        fontWeight: FontWeight.w700,
        color: _primary(context),
        letterSpacing: -0.3,
      );

  static TextStyle titleMedium(BuildContext context) => GoogleFonts.inter(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        color: _primary(context),
        letterSpacing: -0.2,
      );

  static TextStyle titleSmall(BuildContext context) => GoogleFonts.inter(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: _primary(context),
        letterSpacing: 0.5,
      );

  // ── Cuerpo ──────────────────────────────────────────────
  static TextStyle bodyMedium(BuildContext context) => GoogleFonts.inter(
        fontSize: 14,
        fontWeight: FontWeight.w400,
        color: _primary(context),
      );

  static TextStyle bodySmall(BuildContext context) => GoogleFonts.inter(
        fontSize: 12,
        fontWeight: FontWeight.w400,
        color: _secondary(context),
      );

  // ── Etiquetas ────────────────────────────────────────────
  static TextStyle label(BuildContext context) => GoogleFonts.inter(
        fontSize: 11,
        fontWeight: FontWeight.w600,
        color: _secondary(context),
        letterSpacing: 0.8,
      );

  // ── Monospace (log) ──────────────────────────────────────
  static TextStyle mono(BuildContext context) => GoogleFonts.jetBrainsMono(
        fontSize: 11,
        fontWeight: FontWeight.w400,
        color: _primary(context),
        height: 1.5,
      );

  // ── Acento ───────────────────────────────────────────────
  static TextStyle accent({double size = 14}) => GoogleFonts.inter(
        fontSize: size,
        fontWeight: FontWeight.w600,
        color: kAccent,
      );

  // ── Botón ────────────────────────────────────────────────
  static TextStyle button({bool small = false}) => GoogleFonts.inter(
        fontSize: small ? 12 : 14,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.1,
      );

  // ── Helpers privados ─────────────────────────────────────
  static Color _primary(BuildContext context) =>
      Theme.of(context).brightness == Brightness.light
          ? kTextPrimaryLight
          : kTextPrimaryDark;

  static Color _secondary(BuildContext context) =>
      Theme.of(context).brightness == Brightness.light
          ? kTextSecondaryLight
          : kTextSecondaryDark;
}
