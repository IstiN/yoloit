/// Parse the aspect ratio from an SVG string by reading the viewBox attribute.
///
/// Returns `width / height` if the viewBox contains four valid numeric parts,
/// otherwise falls back to `16 / 9`.
double parseSvgAspectRatio(String svg) {
  final match = RegExp(r'viewBox="([^"]+)"').firstMatch(svg);
  if (match != null) {
    final parts = match.group(1)!.trim().split(RegExp(r'[\s,]+'));
    if (parts.length == 4) {
      final width = double.tryParse(parts[2]);
      final height = double.tryParse(parts[3]);
      if (width != null && height != null && width > 0 && height > 0) {
        return width / height;
      }
    }
  }
  return 16 / 9;
}
