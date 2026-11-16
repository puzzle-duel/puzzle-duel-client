part of '../puzzle_duel_rules.dart';

/// Canonical JSON + SHA-256 for CORE-001.v3 (ADR-E01 §8).
///
/// Deterministic integrity encoding only — **not** ranked authenticity.

final class CanonicalJsonException implements Exception {
  CanonicalJsonException(this.message);
  final String message;

  @override
  String toString() => 'CanonicalJsonException($message)';
}

String canonicalJsonV3(Object? value) {
  final buffer = StringBuffer();
  _writeCanonical(buffer, value);
  return buffer.toString();
}

String stateHashV3(GameState state) {
  if (state.rulesVersion != RulesVersion.core001V3) {
    throw CanonicalJsonException('stateHashV3 requires core-001.v3');
  }
  final canonical = canonicalJsonV3(state.toJson());
  return sha256.convert(utf8.encode(canonical)).toString();
}

/// Atom helper for independent CV-* vectors.
String sha256HexOfUtf8(String canonical) =>
    sha256.convert(utf8.encode(canonical)).toString();

void _writeCanonical(StringBuffer out, Object? value) {
  if (value == null) {
    out.write('null');
    return;
  }
  if (value is bool) {
    out.write(value ? 'true' : 'false');
    return;
  }
  if (value is int) {
    if (value < -kJsonMaxSafeInteger || value > kJsonMaxSafeInteger) {
      throw CanonicalJsonException('integer out of JSON-safe range');
    }
    out.write(value.toString());
    return;
  }
  if (value is double) {
    throw CanonicalJsonException('floating-point values are rejected');
  }
  if (value is String) {
    _writeCanonicalString(out, value);
    return;
  }
  if (value is List) {
    out.write('[');
    for (var i = 0; i < value.length; i++) {
      if (i > 0) out.write(',');
      _writeCanonical(out, value[i]);
    }
    out.write(']');
    return;
  }
  if (value is Map) {
    final entries = <MapEntry<String, Object?>>[];
    for (final entry in value.entries) {
      final key = entry.key;
      if (key is! String) {
        throw CanonicalJsonException('non-string object key');
      }
      entries.add(MapEntry(key, entry.value as Object?));
    }
    entries.sort((a, b) => _utf8KeyCompare(a.key, b.key));
    out.write('{');
    for (var i = 0; i < entries.length; i++) {
      if (i > 0) out.write(',');
      _writeCanonicalString(out, entries[i].key);
      out.write(':');
      _writeCanonical(out, entries[i].value);
    }
    out.write('}');
    return;
  }
  throw CanonicalJsonException('unsupported JSON value type');
}

void _writeCanonicalString(StringBuffer out, String value) {
  for (final unit in value.runes) {
    if (unit > 0x7F) {
      throw CanonicalJsonException('non-ASCII string content');
    }
  }
  out.write('"');
  for (var i = 0; i < value.length; i++) {
    final code = value.codeUnitAt(i);
    if (code == 0x22) {
      out.write(r'\"');
    } else if (code == 0x5C) {
      out.write(r'\\');
    } else if (code <= 0x1F) {
      out.write('\\u00');
      out.write(code.toRadixString(16).padLeft(2, '0'));
    } else {
      out.writeCharCode(code);
    }
  }
  out.write('"');
}

int _utf8KeyCompare(String a, String b) {
  final aa = utf8.encode(a);
  final bb = utf8.encode(b);
  final n = aa.length < bb.length ? aa.length : bb.length;
  for (var i = 0; i < n; i++) {
    final d = aa[i] - bb[i];
    if (d != 0) return d;
  }
  return aa.length - bb.length;
}
