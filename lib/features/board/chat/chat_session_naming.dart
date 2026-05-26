String makeUniqueChatSessionName(
  String preferredName,
  Iterable<String> existingNames,
) {
  final baseName = preferredName.trim();
  if (baseName.isEmpty) return preferredName;

  final taken = existingNames.map((name) => name.trim().toLowerCase()).toSet();
  if (!taken.contains(baseName.toLowerCase())) {
    return baseName;
  }

  var suffix = 2;
  while (true) {
    final candidate = '$baseName $suffix';
    if (!taken.contains(candidate.toLowerCase())) {
      return candidate;
    }
    suffix += 1;
  }
}
