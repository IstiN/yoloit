/// Formats a [DateTime] as a human-readable relative string
/// (e.g. "just now", "5m ago", "3h ago").
///
/// [now] is injectable for testing; defaults to [DateTime.now].
String formatTimeAgo(DateTime dt, {DateTime? now}) {
  final reference = now ?? DateTime.now();
  final diff = reference.difference(dt);
  if (diff.inMinutes < 1) return 'just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  if (diff.inDays < 7) return '${diff.inDays}d ago';
  return '${dt.year}-${_two(dt.month)}-${_two(dt.day)}';
}

String _two(int n) => n.toString().padLeft(2, '0');
