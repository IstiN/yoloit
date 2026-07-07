import 'package:yoloit/features/templates/data/template_sources_service_base.dart';
import 'package:yoloit/features/templates/model/template_models.dart';

/// Shared CRUD helpers for VM and web [TemplateSourcesService]s.
///
/// Mix this into a class that implements [loadAll] and [saveAll].
mixin TemplateSourcesServiceCrud {
  /// Loads all configured sources.
  Future<List<TemplateSource>> loadAll();

  /// Persists the given sources.
  Future<void> saveAll(List<TemplateSource> sources);

  /// Adds [source] or updates an existing source with the same id.
  Future<void> addOrUpdate(TemplateSource source) async {
    final sources = await loadAll();
    await saveAll(upsertSource(sources, source));
  }

  /// Removes the source with the given [id].
  Future<void> remove(String id) async {
    final sources = await loadAll();
    await saveAll(removeSource(sources, id));
  }
}
