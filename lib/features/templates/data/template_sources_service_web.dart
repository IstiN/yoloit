import 'package:shared_preferences/shared_preferences.dart';
import 'package:yoloit/features/templates/data/template_sources_service_base.dart';
import 'package:yoloit/features/templates/data/template_sources_service_crud.dart';
import 'package:yoloit/features/templates/model/template_models.dart';

/// Persists the user's configured template sources on the web.
///
/// Sources are stored in browser storage ([SharedPreferences]) instead of the
/// local file system. A built-in source pointing at the bundled
/// `yoloit/templates` assets is always returned first, followed by the default
/// GitHub source (which is a no-op on the web because CORS blocks the GitHub
/// Contents API).
class TemplateSourcesService with TemplateSourcesServiceCrud {
  TemplateSourcesService._();

  static final instance = TemplateSourcesService._();

  static const _storageKey = 'template_sources';

  TemplateSource get defaultSource => buildDefaultSource();

  /// A local source pointing at the built-in templates that ship with the
  /// repository as Flutter assets.
  TemplateSource get builtInSource => const TemplateSource(
    id: 'yoloit-builtins',
    type: TemplateSourceType.local,
    localPath: 'yoloit/templates',
  );

  Future<List<TemplateSource>> loadAll() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_storageKey);
    List<TemplateSource> sources;
    if (raw == null || raw.trim().isEmpty) {
      sources = [builtInSource, defaultSource];
      return sources;
    }
    try {
      sources = parseSourcesJson(raw);
    } catch (e) {
      debugLogSourceError('[TemplateSourcesService] loadAll error', e);
      sources = [];
    }
    sources = ensureBuiltinSources(
      sources,
      defaultSource: defaultSource,
      builtInSource: builtInSource,
    );
    return sources;
  }

  Future<void> saveAll(List<TemplateSource> sources) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_storageKey, encodeSourcesJson(sources));
  }
}
