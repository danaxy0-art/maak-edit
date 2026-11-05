import 'package:flutter/material.dart';

// Visual tokens for the redesign. Colours are sampled from the approved
// Mental Health onboarding reference; border, shadow and onHero were derived
// and approved separately. Screens adopt these one stage at a time, so
// AppColors stays in place for everything not yet migrated.

class MaakColors {
  static const ink = Color(0xFF1B1B1B);
  static const button = Color(0xFF232323);
  static const icon = Color(0xFF292D32);
  static const muted = Color(0xFF5B5B5B);
  static const onHero = Color(0xFF4A4A4A);

  static const canvasTop = Color(0xFFFFEFEF);
  static const canvasMid = Color(0xFFFEF8F8);
  static const canvasBottom = Color(0xFFFFFEFE);
  static const surface = Colors.white;
  static const warmWhite = Color(0xFFFFFDFD);
  static const blush = Color(0xFFFFEFEF);
  static const selected = Color(0xFFFED8D5);
  static const fill = Color(0xFFF4F1F1);
  static const border = Color(0xFFF1E4E4);

  static const coral = Color(0xFFF38184);
  static const coralLight = Color(0xFFF8AC93);
  static const coralDeep = Color(0xFFF27781);
  static const orbPink = Color(0xFFFFD3E5);
  static const orbBlush = Color(0xFFFED8D5);
  static const orbPeach = Color(0xFFFDDFC5);

  static const error = Color(0xFFD92D36);
  static const success = Color(0xFF22854D);
}

class MaakGradients {
  static const canvas = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [
      MaakColors.canvasTop,
      MaakColors.canvasMid,
      MaakColors.canvasBottom,
    ],
    stops: [0, .4, 1],
  );

  /// The glowing "orb" from the reference; used once per screen at most.
  static const orb = RadialGradient(
    center: AlignmentDirectional.topEnd,
    radius: 1.4,
    colors: [MaakColors.orbPink, MaakColors.orbBlush, MaakColors.orbPeach],
    stops: [0, .48, 1],
  );

  static const coral = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [MaakColors.coralLight, MaakColors.coralDeep],
  );
}

class MaakSpace {
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 20.0;
  static const xxl = 24.0;
  static const xxxl = 32.0;
}

class MaakRadius {
  static const card = 16.0;
  static const hero = 20.0;
  static const pill = 999.0;
}

class MaakShadows {
  /// Blush-brown at 8%: lifts white cards off the blush canvas, barely visible.
  static const card = [
    BoxShadow(color: Color(0x14AA6464), blurRadius: 10, offset: Offset(0, 2)),
  ];
}

class MaakBreakpoints {
  static const tablet = 600.0;
  static const phoneMaxContent = 560.0;
  static const tabletMaxContent = 1040.0;
}

class MaakText {
  static const family = 'DMSans';

  /// DM Serif Display is kept for personal headings: the greeting, a
  /// volunteer's name and the matching introduction.
  static const greeting = TextStyle(
    fontFamily: 'MaakSerif',
    fontSize: 27,
    height: 1.15,
    color: MaakColors.ink,
  );
  static const pageTitle = TextStyle(
    fontFamily: family,
    fontSize: 22,
    height: 1.25,
    fontWeight: FontWeight.w600,
    color: MaakColors.ink,
  );
  static const cardTitle = TextStyle(
    fontFamily: family,
    fontSize: 20,
    height: 1.25,
    fontWeight: FontWeight.w600,
    color: MaakColors.ink,
  );
  static const section = TextStyle(
    fontFamily: family,
    fontSize: 17,
    height: 1.3,
    fontWeight: FontWeight.w600,
    color: MaakColors.ink,
  );
  static const itemTitle = TextStyle(
    fontFamily: family,
    fontSize: 15,
    height: 1.3,
    fontWeight: FontWeight.w600,
    color: MaakColors.ink,
  );
  static const body = TextStyle(
    fontFamily: family,
    fontSize: 14,
    height: 1.45,
    color: MaakColors.muted,
  );
  static const caption = TextStyle(
    fontFamily: family,
    fontSize: 12,
    height: 1.3,
    fontWeight: FontWeight.w500,
    color: MaakColors.muted,
  );
  static const number = TextStyle(
    fontFamily: family,
    fontSize: 30,
    height: 1.1,
    fontWeight: FontWeight.w600,
    color: MaakColors.ink,
    fontFeatures: [FontFeature.tabularFigures()],
  );
  static const button = TextStyle(
    fontFamily: family,
    fontSize: 15,
    fontWeight: FontWeight.w600,
  );
}
