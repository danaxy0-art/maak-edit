import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../design/tokens.dart';

// The names below predate the redesign and are used across every screen, so
// they are kept and pointed at the approved Ma'ak palette instead of renamed:
// "navy" is now the near-black ink and button colour, the cream background is
// the warm blush canvas, and the blue selection tints are blush.
class AppColors {
  static const primaryNavy = MaakColors.button;
  static const primaryNavyDark = MaakColors.ink;
  static const background = MaakColors.canvasMid;
  static const fieldFill = Colors.white;
  static const fieldBorder = Color(0xFFE6D6D6);
  static const textDark = MaakColors.ink;
  static const textMuted = MaakColors.muted;
  static const selectedCardBorder = MaakColors.coral;
  static const selectedCardFill = MaakColors.blush;
  static const divider = MaakColors.border;
  static const error = MaakColors.error;
  static const success = MaakColors.success;
}

class AppTheme {
  /// Phone status bar and Android navigation bar: transparent, with dark icons
  /// so the clock and battery stay readable on the light Ma'ak backgrounds.
  static const systemBars = SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.dark, // Android
    statusBarBrightness: Brightness.light, // iOS
    systemNavigationBarColor: MaakColors.canvasBottom,
    systemNavigationBarIconBrightness: Brightness.dark,
    systemNavigationBarDividerColor: Colors.transparent,
  );

  static ThemeData light() {
    final scheme = ColorScheme.fromSeed(
      seedColor: MaakColors.coral,
      primary: MaakColors.button,
      onPrimary: Colors.white,
      secondary: MaakColors.coral,
      secondaryContainer: MaakColors.selected,
      onSecondaryContainer: MaakColors.ink,
      primaryContainer: MaakColors.selected,
      onPrimaryContainer: MaakColors.ink,
      surface: MaakColors.surface,
      onSurface: MaakColors.ink,
      onSurfaceVariant: MaakColors.muted,
      surfaceContainerHighest: MaakColors.fill,
      outline: AppColors.fieldBorder,
      outlineVariant: MaakColors.border,
      error: MaakColors.error,
      brightness: Brightness.light,
    );
    OutlineInputBorder border(Color color, [double width = 1]) =>
        OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: color, width: width),
        );
    const pill = StadiumBorder();
    return ThemeData(
      useMaterial3: true,
      fontFamily: MaakText.family,
      colorScheme: scheme,
      scaffoldBackgroundColor: MaakColors.canvasMid,
      textTheme: ThemeData.light().textTheme.apply(
        fontFamily: MaakText.family,
        bodyColor: MaakColors.ink,
        displayColor: MaakColors.ink,
      ),
      iconTheme: const IconThemeData(color: MaakColors.icon),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        foregroundColor: MaakColors.ink,
        iconTheme: IconThemeData(color: MaakColors.icon),
        centerTitle: false,
        titleTextStyle: MaakText.pageTitle,
        // Screens with an AppBar would otherwise pick their own status bar style.
        systemOverlayStyle: systemBars,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 15,
        ),
        hintStyle: MaakText.body,
        labelStyle: MaakText.body,
        errorMaxLines: 3,
        border: border(AppColors.fieldBorder),
        enabledBorder: border(AppColors.fieldBorder),
        disabledBorder: border(MaakColors.border),
        focusedBorder: border(MaakColors.button, 1.5),
        errorBorder: border(MaakColors.error),
        focusedErrorBorder: border(MaakColors.error, 1.5),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: MaakColors.button,
          foregroundColor: Colors.white,
          disabledBackgroundColor: MaakColors.fill,
          disabledForegroundColor: MaakColors.muted,
          minimumSize: const Size(double.infinity, 52),
          elevation: 0,
          shape: pill,
          textStyle: MaakText.button.copyWith(fontSize: 16),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: MaakColors.button,
          foregroundColor: Colors.white,
          disabledBackgroundColor: MaakColors.fill,
          disabledForegroundColor: MaakColors.muted,
          minimumSize: const Size(100, 48),
          shape: pill,
          textStyle: MaakText.button,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: MaakColors.ink,
          backgroundColor: MaakColors.surface,
          minimumSize: const Size(100, 48),
          side: const BorderSide(color: MaakColors.button, width: 1.5),
          shape: pill,
          textStyle: MaakText.button,
        ),
      ),
      cardTheme: const CardThemeData(
        color: MaakColors.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(MaakRadius.card)),
          side: BorderSide(color: MaakColors.border),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: MaakColors.surface,
        titleTextStyle: MaakText.cardTitle,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(22)),
        ),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: MaakColors.warmWhite,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        dragHandleColor: MaakColors.border,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: MaakColors.button,
        contentTextStyle: MaakText.body.copyWith(color: Colors.white),
        actionTextColor: MaakColors.orbBlush,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: MaakColors.fill,
        // Selected filters use the black button theme with white text.
        selectedColor: MaakColors.button,
        checkmarkColor: Colors.white,
        side: const BorderSide(color: MaakColors.border),
        labelStyle: MaakText.caption.copyWith(
          color: WidgetStateColor.resolveWith(
            (s) => s.contains(WidgetState.selected)
                ? Colors.white
                : MaakColors.ink,
          ),
        ),
        shape: pill,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? Colors.white : null,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? MaakColors.button : null,
        ),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? MaakColors.button : null,
        ),
        checkColor: const WidgetStatePropertyAll(Colors.white),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
      ),
      radioTheme: const RadioThemeData(
        fillColor: WidgetStatePropertyAll(MaakColors.button),
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: MaakColors.ink,
        unselectedLabelColor: MaakColors.muted,
        indicatorColor: MaakColors.button,
        dividerColor: MaakColors.border,
        labelStyle: MaakText.button.copyWith(fontSize: 14),
        unselectedLabelStyle: MaakText.button.copyWith(
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          // Selected filters use the black button theme with white text.
          backgroundColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected)
                ? MaakColors.button
                : MaakColors.surface,
          ),
          foregroundColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected)
                ? Colors.white
                : MaakColors.ink,
          ),
          side: const WidgetStatePropertyAll(
            BorderSide(color: AppColors.fieldBorder),
          ),
        ),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: MaakColors.ink,
        linearTrackColor: MaakColors.fill,
      ),
      listTileTheme: const ListTileThemeData(
        iconColor: MaakColors.icon,
        textColor: MaakColors.ink,
      ),
      popupMenuTheme: const PopupMenuThemeData(
        color: MaakColors.surface,
        surfaceTintColor: Colors.transparent,
      ),
      dropdownMenuTheme: const DropdownMenuThemeData(
        menuStyle: MenuStyle(
          backgroundColor: WidgetStatePropertyAll(MaakColors.surface),
          surfaceTintColor: WidgetStatePropertyAll(Colors.transparent),
        ),
      ),
      textSelectionTheme: const TextSelectionThemeData(
        cursorColor: MaakColors.ink,
        selectionColor: MaakColors.selected,
        selectionHandleColor: MaakColors.coral,
      ),
      dividerTheme: const DividerThemeData(color: MaakColors.border),
    );
  }
}
