import 'package:material_ui/material_ui.dart';

/// Every value from `docs/design-tokens.md`. Widgets read these through
/// `Theme.of(context).extension<ThottamTokens>()`, never as literals.
/// Where the doc gives a range, the value is the one the prototype uses most.
@immutable
class ThottamTokens extends ThemeExtension<ThottamTokens> {
  const ThottamTokens._();

  static const standard = ThottamTokens._();

  // Colour
  Color get ground => const Color(0xFFF4F6F1);
  Color get surface => const Color(0xFFFFFFFF);
  Color get ink => const Color(0xFF14201A);
  Color get muted => const Color(0xFF56635B);
  Color get line => const Color(0xFFDDE3DA);
  Color get lineSoft => const Color(0xFFECEFEA);
  Color get primary => const Color(0xFF1B6B3A);
  Color get onPrimary => const Color(0xFFFFFFFF);
  Color get primaryDark => const Color(0xFF0F3D22);
  Color get primaryTint => const Color(0xFFE9F3EB);
  Color get primaryPill => const Color(0xFFD5EBDA);
  Color get accent => const Color(0xFFF2B01E);
  Color get accentTint => const Color(0xFFFFF1C7);
  Color get onAccentTint => const Color(0xFF6B4A00);
  Color get onAccentTintStrong => const Color(0xFF3D2A00);
  Color get noticeBg => const Color(0xFFFFF6DC);
  Color get noticeLine => const Color(0xFFEBCB73);
  Color get expense => const Color(0xFFE08A1E);
  Color get expenseTint => const Color(0xFFFBEEDD);
  Color get onExpenseTint => const Color(0xFF8A4B00);
  Color get onExpenseTintStrong => const Color(0xFF6E4310);
  Color get negativeTint => const Color(0xFFFBE3D2);
  Color get onNegativeTint => const Color(0xFF7A2E05);
  Color get danger => const Color(0xFFB4440A);
  Color get onDanger => const Color(0xFF8A3306);
  Color get infoTint => const Color(0xFFE4ECF7);
  Color get onInfoTint => const Color(0xFF1F4E8C);
  Color get onInfoTintStrong => const Color(0xFF14335E);
  Color get switchOff => const Color(0xFF8B978D);
  Color get toast => const Color(0xFF14201A);
  Color get onToast => const Color(0xFFFFFFFF);
  Color get chipBorder => const Color(0xFFC3CBC1);
  Color get segmentTrack => const Color(0xFFE3E8E0);

  // Type
  String get headingFamily => 'AnekMalayalam';
  String get bodyFamily => 'Inter';
  List<String> get bodyFallback => const ['NotoSansMalayalam'];
  double get displaySize => 40;
  double get screenTitleSize => 26;
  double get sectionTitleSize => 19;
  double get cardTitleSize => 17;
  double get bodySize => 15;
  double get captionSize => 14;
  double get tabLabelSize => 12;
  double get primaryButtonTextSize => 18;
  double get stepperNumberSize => 26;
  double get lineHeight => 1.5;
  double get largeTextScale => 1.12;

  // Shape and spacing
  double get screenPadding => 20;
  double get cardGap => 14;
  double get cardPadding => 16;
  double get cardRadius => 20;
  double get buttonRadius => 16;
  double get chipRadius => 999;
  double get tileRadius => 14;
  double get sheetRadius => 28;
  double get minTouch => 48;
  double get primaryButtonHeight => 58;
  double get listRowMin => 56;
  double get listRowMax => 68;
  double get navHeight => 78;
  double get addButtonSize => 62;
  double get addButtonRaise => 34;
  // Same cap Material's NavigationBar uses, so labels fit the fixed bar at
  // the largest system text size.
  double get navLabelMaxScale => 1.3;
  double get outlineWidth => 1.5;

  // Components
  double get switchWidth => 54;
  double get switchHeight => 34;
  double get switchKnob => 28;
  double get stepperButton => 48;
  double get tintTileSmall => 40;
  double get tintTileLarge => 52;
  double get iconSize => 24;
  double get iconStroke => 2;

  // Motion (all off when the system asks for reduced motion)
  Duration get entry => const Duration(milliseconds: 380);
  double get entryRise => 16;
  Duration get entryStagger => const Duration(milliseconds: 50);
  Curve get entryCurve => const Cubic(0.2, 0.8, 0.2, 1);
  Duration get sheetSlide => const Duration(milliseconds: 360);
  Duration get scrimFade => const Duration(milliseconds: 220);
  Duration get barGrow => const Duration(milliseconds: 800);
  Duration get barResize => const Duration(milliseconds: 450);
  Duration get switchKnobMove => const Duration(milliseconds: 240);
  double get pressScale => 0.95;
  // The doc gives no press duration; short enough to feel immediate.
  Duration get pressDuration => const Duration(milliseconds: 100);
  Duration get toastIn => const Duration(milliseconds: 320);
  Duration get toastStay => const Duration(milliseconds: 1900);

  // shortcut: one fixed token set, so copyWith and lerp return it unchanged;
  // add fields here if a dark or high-contrast theme is ever designed.
  @override
  ThottamTokens copyWith() => this;

  @override
  ThottamTokens lerp(ThottamTokens? other, double t) => this;
}

extension TokensOf on BuildContext {
  ThottamTokens get tokens => Theme.of(this).extension<ThottamTokens>()!;
}
