/// Splits an AI answer into normal text and generated-file blocks:
///   <<<FILE: name.ext>>> ... <<<END FILE>>>
sealed class Seg {}

class TextSeg extends Seg {
  TextSeg(this.text);
  final String text;
}

class FileSeg extends Seg {
  FileSeg(this.name, this.content, this.done);
  final String name;
  final String content;
  final bool done; // false while the file is still streaming in
}

const _open = '<<<FILE:';
const _close = '<<<END FILE>>>';

/// Hides a half-typed marker (e.g. "<<<FI") at the very end of streaming text.
String _trimPartial(String s, String marker) {
  for (var n = marker.length - 1; n > 0; n--) {
    if (s.endsWith(marker.substring(0, n))) return s.substring(0, s.length - n);
  }
  return s;
}

String _unfence(String c) {
  var t = c.trim();
  if (t.startsWith('```')) {
    final nl = t.indexOf('\n');
    if (nl > 0) t = t.substring(nl + 1);
    if (t.trimRight().endsWith('```')) {
      t = t.trimRight();
      t = t.substring(0, t.length - 3);
    }
  }
  return t.trimRight();
}

List<Seg> parseSegments(String s) {
  if (!s.contains('<<<')) return [TextSeg(s)];
  final out = <Seg>[];
  var i = 0;
  while (i < s.length) {
    final o = s.indexOf(_open, i);
    if (o < 0) {
      final rest = _trimPartial(s.substring(i), _open);
      if (rest.trim().isNotEmpty) out.add(TextSeg(rest));
      break;
    }
    final before = s.substring(i, o);
    if (before.trim().isNotEmpty) out.add(TextSeg(before));
    final nameEnd = s.indexOf('>>>', o + _open.length);
    if (nameEnd < 0) break; // header still streaming
    final name = s.substring(o + _open.length, nameEnd).trim();
    final bodyStart = nameEnd + 3;
    final c = s.indexOf(_close, bodyStart);
    if (c < 0) {
      out.add(FileSeg(name, _unfence(_trimPartial(s.substring(bodyStart), _close)), false));
      break;
    }
    out.add(FileSeg(name, _unfence(s.substring(bodyStart, c)), true));
    i = c + _close.length;
  }
  return out.isEmpty ? [TextSeg('')] : out;
}

List<FileSeg> completedFiles(String s) => parseSegments(s).whereType<FileSeg>().where((f) => f.done && f.name.isNotEmpty).toList();
