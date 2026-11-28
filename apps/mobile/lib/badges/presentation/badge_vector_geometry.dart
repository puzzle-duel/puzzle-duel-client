import 'package:flutter/painting.dart';

/// Shared vector helpers for the canonical 280×240 badge canvas.
final class BadgeVectorGeometry {
  const BadgeVectorGeometry._();

  static const double viewBoxWidth = 280;
  static const double viewBoxHeight = 240;
  static const Offset medallionCenter = Offset(140, 103);
  static const double auraRadius = 103;
  static const double medallionRadius = 71;
  static const double innerBorderRadius = 60;
  static const double mythicOrbitRadius = 94;

  static const Rect countCapsule = Rect.fromLTWH(105, 153, 70, 28);
  static const double countCapsuleRadius = 14;
  static const Offset countTextCenter = Offset(140, 172);
  static const Offset prestigeLabelBaseline = Offset(140, 211);

  static Path diamondOrnament({
    required double tipY,
    required double midY,
    required double baseY,
    required double halfWidth,
  }) {
    final cx = medallionCenter.dx;
    return Path()
      ..moveTo(cx, tipY)
      ..lineTo(cx + halfWidth, midY)
      ..lineTo(cx, baseY)
      ..lineTo(cx - halfWidth, midY)
      ..close();
  }

  /// First ornament layer base: M140 19 L148 38 L140 46 L132 38 Z
  static Path firstOrnamentBase() => diamondOrnament(
    tipY: 19,
    midY: 38,
    baseY: 46,
    halfWidth: 8,
  );

  /// Second ornament layer base: M140 7 L145 17 L140 27 L135 17 Z
  static Path secondOrnamentBase() => diamondOrnament(
    tipY: 7,
    midY: 17,
    baseY: 27,
    halfWidth: 5,
  );

  /// Minimal SVG path subset used by badge center artwork (M L H V C Q Z).
  static Path parseSvgPath(String d) {
    final path = Path();
    final tokens = _svgTokens(d);
    var i = 0;
    var cx = 0.0;
    var cy = 0.0;
    String? command;

    double next() {
      if (i >= tokens.length) {
        throw FormatException('Unexpected end of path');
      }
      return double.parse(tokens[i++]);
    }

    while (i < tokens.length) {
      final token = tokens[i];
      if (_isCommand(token)) {
        command = token;
        i++;
      } else if (command == null) {
        throw FormatException('Path data missing command at $token');
      }

      switch (command) {
        case 'M':
          cx = next();
          cy = next();
          path.moveTo(cx, cy);
          command = 'L';
        case 'L':
          cx = next();
          cy = next();
          path.lineTo(cx, cy);
        case 'H':
          cx = next();
          path.lineTo(cx, cy);
        case 'V':
          cy = next();
          path.lineTo(cx, cy);
        case 'C':
          final x1 = next();
          final y1 = next();
          final x2 = next();
          final y2 = next();
          cx = next();
          cy = next();
          path.cubicTo(x1, y1, x2, y2, cx, cy);
        case 'Q':
          final x1 = next();
          final y1 = next();
          cx = next();
          cy = next();
          path.quadraticBezierTo(x1, y1, cx, cy);
        case 'Z':
        case 'z':
          path.close();
          command = null;
        default:
          throw FormatException('Unsupported path command $command');
      }
    }
    return path;
  }

  static bool _isCommand(String token) =>
      token.length == 1 && RegExp(r'[A-Za-z]').hasMatch(token);

  static List<String> _svgTokens(String d) {
    final out = <String>[];
    final buffer = StringBuffer();
    void flush() {
      if (buffer.isNotEmpty) {
        out.add(buffer.toString());
        buffer.clear();
      }
    }

    for (var i = 0; i < d.length; i++) {
      final ch = d[i];
      if (RegExp(r'[A-Za-z]').hasMatch(ch)) {
        flush();
        out.add(ch);
      } else if (ch == ',' || ch == ' ' || ch == '\n' || ch == '\t') {
        flush();
      } else if (ch == '-' && buffer.isNotEmpty) {
        flush();
        buffer.write(ch);
      } else {
        buffer.write(ch);
      }
    }
    flush();
    return out;
  }
}
