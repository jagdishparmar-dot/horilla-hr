import 'package:flutter/material.dart';

/// ClockMe home type: Geist headlines, Inter body — same pairing as the Stitch screen.
abstract final class HomeType {
  static const headlineFamily = 'Geist';
  static const bodyFamily = 'Inter';

  static TextStyle headline({
    TextStyle? textStyle,
    Color? color,
    double? fontSize,
    FontWeight? fontWeight,
    double? letterSpacing,
    double? height,
    List<FontFeature>? fontFeatures,
  }) {
    return (textStyle ?? const TextStyle()).copyWith(
      fontFamily: headlineFamily,
      color: color,
      fontSize: fontSize,
      fontWeight: fontWeight,
      letterSpacing: letterSpacing,
      height: height,
      fontFeatures: fontFeatures,
    );
  }

  static TextStyle body({
    TextStyle? textStyle,
    Color? color,
    double? fontSize,
    FontWeight? fontWeight,
    double? letterSpacing,
    double? height,
  }) {
    return (textStyle ?? const TextStyle()).copyWith(
      fontFamily: bodyFamily,
      color: color,
      fontSize: fontSize,
      fontWeight: fontWeight,
      letterSpacing: letterSpacing,
      height: height,
    );
  }

  static ThemeData of(BuildContext context) {
    final base = Theme.of(context);
    return base.copyWith(
      textTheme: base.textTheme.apply(fontFamily: bodyFamily),
      primaryTextTheme: base.primaryTextTheme.apply(fontFamily: bodyFamily),
    );
  }
}
