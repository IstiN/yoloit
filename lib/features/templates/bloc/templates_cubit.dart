import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:yoloit/features/templates/data/template_service.dart';
import 'package:yoloit/features/templates/model/template_models.dart';

class TemplatesState extends Equatable {
  const TemplatesState({
    this.templates = const [],
    this.selectedTemplate,
    this.isLoading = false,
    this.error,
  });

  final List<BoardTemplate> templates;
  final BoardTemplate? selectedTemplate;
  final bool isLoading;
  final String? error;

  TemplatesState copyWith({
    List<BoardTemplate>? templates,
    BoardTemplate? selectedTemplate,
    bool? isLoading,
    String? error,
    bool clearSelected = false,
  }) => TemplatesState(
    templates: templates ?? this.templates,
    selectedTemplate:
        clearSelected ? null : (selectedTemplate ?? this.selectedTemplate),
    isLoading: isLoading ?? this.isLoading,
    error: error ?? this.error,
  );

  @override
  List<Object?> get props => [templates, selectedTemplate, isLoading, error];
}

class TemplatesCubit extends Cubit<TemplatesState> {
  TemplatesCubit({BoardTemplateService? service})
    : _service = service ?? BoardTemplateService.instance,
      super(const TemplatesState());

  final BoardTemplateService _service;

  Future<void> load() async {
    emit(state.copyWith(isLoading: true, error: null));
    try {
      var templates = await _service.loadAll();
      if (templates.isEmpty) {
        templates = await _service.sync();
      }
      emit(state.copyWith(templates: templates, isLoading: false));
    } catch (e) {
      emit(state.copyWith(isLoading: false, error: e.toString()));
    }
  }

  Future<void> sync() async {
    emit(state.copyWith(isLoading: true, error: null));
    try {
      final templates = await _service.sync();
      emit(state.copyWith(templates: templates, isLoading: false));
    } catch (e) {
      emit(state.copyWith(isLoading: false, error: e.toString()));
    }
  }

  void selectTemplate(BoardTemplate? template) {
    emit(state.copyWith(selectedTemplate: template));
  }

  Map<String, String> validateParameters(
    BoardTemplate template,
    Map<String, dynamic> values,
  ) => _service.validateParameters(template, values);

  Map<String, dynamic> buildEffectiveParameters(
    BoardTemplate template,
    Map<String, dynamic> values,
  ) => _service.buildEffectiveParameters(template, values);
}
