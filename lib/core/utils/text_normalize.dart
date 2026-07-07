/// Removes trailing whitespace per line, strips leading/trailing blank lines,
/// collapses long runs of empty lines and strips ANSI escape sequences so
/// terminal selections do not fall back to temp files just because they
/// contain color codes.
String normalizeText(String text) {
  final withoutAnsi = text.replaceAll(
    RegExp(r'\x1B\[[\d;]*[A-Za-z]'),
    '',
  );
  final lines = withoutAnsi.split(RegExp(r'\r?\n'));
  final cleaned = <String>[];
  var blankRun = 0;
  for (final raw in lines) {
    final line = raw.trimRight();
    if (line.isEmpty) {
      blankRun++;
      if (blankRun <= 1) cleaned.add('');
    } else {
      blankRun = 0;
      cleaned.add(line);
    }
  }
  while (cleaned.isNotEmpty && cleaned.first.isEmpty) {
    cleaned.removeAt(0);
  }
  while (cleaned.isNotEmpty && cleaned.last.isEmpty) {
    cleaned.removeLast();
  }
  return cleaned.join('\n');
}
