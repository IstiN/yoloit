/// Live readers for form fields keyed by JSON `id` / `storageKey`.
class UiViewFieldRegistry {
  final Map<String, String Function()> _readers = <String, String Function()>{};

  void register(String id, String Function() read) {
    if (id.isEmpty) return;
    _readers[id] = read;
  }

  void unregister(String id) {
    _readers.remove(id);
  }

  Map<String, dynamic> snapshot() {
    final out = <String, dynamic>{};
    for (final entry in _readers.entries) {
      out[entry.key] = entry.value();
    }
    return out;
  }
}
