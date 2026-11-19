import 'package:material_ui/material_ui.dart';

import '../theme/tokens.dart';

/// The Thottam mark: a coconut palm against the sun, without its tile.
/// Drawn for a primary background, where it matches the launcher icon.
/// Decorative: the app name is always shown next to it.
class ThottamMark extends StatelessWidget {
  const ThottamMark({super.key, this.size = 72});

  final double size;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return CustomPaint(
      size: Size.square(size),
      painter: _MarkPainter(sun: t.accent, palm: t.ground),
    );
  }
}

class _MarkPainter extends CustomPainter {
  _MarkPainter({required this.sun, required this.palm});

  final Color sun;
  final Color palm;

  // The palm from design/logo/thottam-logo.svg, in its 96 grid. Each part is
  // its own path so overlaps fill like the SVG's separate <path> elements.
  static final List<Path> _palm = [
    _frond(const [38, 28, 21, 29, 13, 46], const [24, 36, 37, 37]),
    _frond(const [45, 27, 34, 17, 21, 15], const [31, 23, 41, 32]),
    _frond(const [52, 28, 62, 19, 75, 17], const [65, 25, 55, 33]),
    _frond(const [59, 31, 74, 33, 83, 49], const [72, 39, 59, 39]),
    Path()
      ..moveTo(39, 80)
      ..cubicTo(41, 66, 44, 55, 46.5, 45)
      ..lineTo(51.5, 46)
      ..cubicTo(49, 57, 46, 67, 45, 80)
      ..cubicTo(45, 83, 39, 83, 39, 80)
      ..close(),
    Path()
      ..addOval(Rect.fromCircle(center: const Offset(48.5, 45), radius: 4.5)),
  ];

  /// A frond from the crown (48, 44) out along [out] and back along [back].
  static Path _frond(List<double> out, List<double> back) => Path()
    ..moveTo(48, 44)
    ..cubicTo(out[0], out[1], out[2], out[3], out[4], out[5])
    ..cubicTo(back[0], back[1], back[2], back[3], 48, 44)
    ..close();

  @override
  void paint(Canvas canvas, Size size) {
    // The mark fills the square from (13, 14) to (83, 84) of the 96 grid.
    canvas
      ..scale(size.width / 70)
      ..translate(-13, -14)
      ..saveLayer(null, Paint())
      ..drawCircle(const Offset(56, 38), 23, Paint()..color = sun);
    // A 3.5 gap between palm and sun, as the SVG's mask, so it reads in one
    // colour too.
    final gap = Paint()
      ..blendMode = BlendMode.clear
      ..style = PaintingStyle.stroke
      ..strokeWidth = 7
      ..strokeJoin = StrokeJoin.round;
    final fill = Paint()..color = palm;
    for (final part in _palm) {
      canvas.drawPath(part, gap);
    }
    for (final part in _palm) {
      canvas.drawPath(part, fill);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_MarkPainter old) => old.sun != sun || old.palm != palm;
}
