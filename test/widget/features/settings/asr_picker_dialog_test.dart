import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yoloit/core/theme/app_theme.dart';
import 'package:yoloit/features/settings/data/cloud_llm_settings_service.dart';
import 'package:yoloit/features/settings/ui/dialogs/asr_picker_dialog.dart';

typedef AsrResult = ({String mode, String? configId, String? model});

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const openRouter = CloudLlmConfig(
    id: 'openrouter',
    name: 'OpenRouter',
    baseUrl: 'https://openrouter.ai/api/v1',
    apiKey: 'key',
    model: '',
  );
  const customProvider = CloudLlmConfig(
    id: 'my-local-proxy',
    name: 'Local Proxy',
    baseUrl: 'http://localhost:1234',
    apiKey: '',
    model: '',
  );

  AsrResult? result;

  Future<void> openDialog(
    WidgetTester tester, {
    bool showDefaultOption = false,
    String initialMode = 'local',
    String? initialConfigId,
    String? initialModel,
    List<CloudLlmConfig> cloudConfigs = const [openRouter],
  }) async {
    result = null;
    tester.view.physicalSize = const Size(1600, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppThemePreset.neonPurple.theme,
        home: Scaffold(
          body: Builder(
            builder:
                (context) => ElevatedButton(
                  onPressed: () async {
                    result = await showDialog<AsrResult>(
                      context: context,
                      builder:
                          (_) => AsrPickerDialog(
                            showDefaultOption: showDefaultOption,
                            initialMode: initialMode,
                            initialConfigId: initialConfigId,
                            initialModel: initialModel,
                            cloudConfigs: cloudConfigs,
                          ),
                    );
                  },
                  child: const Text('open'),
                ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('shows default segment only when requested', (tester) async {
    await openDialog(tester, showDefaultOption: true);
    expect(find.text('Default'), findsOneWidget);
    expect(find.text('Local'), findsOneWidget);
    expect(find.text('Cloud'), findsOneWidget);

    // Cancel dismisses without a result.
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(result, isNull);

    await openDialog(tester, showDefaultOption: false);
    expect(find.text('Default'), findsNothing);
  });

  testWidgets('cloud mode reveals provider and catalog model pickers', (
    tester,
  ) async {
    await openDialog(tester);

    // Cloud-only fields hidden in local mode.
    expect(find.text('Provider'), findsNothing);

    await tester.tap(find.text('Cloud'));
    await tester.pumpAndSettle();
    expect(find.text('Provider'), findsOneWidget);
    expect(find.text('Model'), findsOneWidget);

    // Pick the provider from the dropdown.
    await tester.tap(find.text('Select provider'), warnIfMissed: false);
    await tester.pumpAndSettle();
    await tester.tap(find.text('OpenRouter').last);
    await tester.pumpAndSettle();

    // Catalog-backed model dropdown appears; pick a catalog model.
    await tester.tap(find.text('Select model'), warnIfMissed: false);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Gemma 4 31B').last);
    await tester.pumpAndSettle();

    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    expect(result, isNotNull);
    expect(result!.mode, 'cloud');
    expect(result!.configId, 'openrouter');
    expect(result!.model, 'google/gemma-4-31b-it');
  });

  testWidgets('falls back to a free-text model field for unknown providers', (
    tester,
  ) async {
    await openDialog(
      tester,
      initialMode: 'cloud',
      cloudConfigs: const [customProvider],
    );

    await tester.tap(find.text('Select provider'), warnIfMissed: false);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Local Proxy').last);
    await tester.pumpAndSettle();

    // No catalog: single free-text field with the whisper hint.
    expect(find.text('Select model'), findsNothing);
    await tester.enterText(find.byType(TextField), 'whisper-1');

    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    expect(result, isNotNull);
    expect(result!.mode, 'cloud');
    expect(result!.configId, 'my-local-proxy');
    expect(result!.model, 'whisper-1');
  });
}
