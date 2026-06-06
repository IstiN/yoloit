import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yoloit/features/board/chat/widgets/chat_model_suggestions.dart';
import 'package:yoloit/features/board/model/chat_models.dart';

void main() {
  group('ChatModelSuggestions', () {
    testWidgets('shows empty state when no models', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ChatModelSuggestions(
              models: const [],
              selectedIndex: 0,
              currentModelId: 'm1',
              scrollController: ScrollController(),
              onSelect: (_) {},
            ),
          ),
        ),
      );

      expect(find.text('No models found'), findsOneWidget);
    });

    testWidgets('renders model names and selects on tap', (tester) async {
      String? selectedId;
      final models = [
        const ChatModelInfo(id: 'm1', displayName: 'GPT-4'),
        const ChatModelInfo(id: 'm2', displayName: 'Claude'),
      ];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ChatModelSuggestions(
              models: models,
              selectedIndex: 0,
              currentModelId: 'm1',
              scrollController: ScrollController(),
              onSelect: (id) => selectedId = id,
            ),
          ),
        ),
      );

      expect(find.text('GPT-4'), findsOneWidget);
      expect(find.text('Claude'), findsOneWidget);

      await tester.tap(find.text('Claude'));
      expect(selectedId, 'm2');
    });

    testWidgets('marks current model with check icon', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ChatModelSuggestions(
              models: const [
                ChatModelInfo(id: 'm1', displayName: 'GPT-4'),
                ChatModelInfo(id: 'm2', displayName: 'Claude'),
              ],
              selectedIndex: 0,
              currentModelId: 'm1',
              scrollController: ScrollController(),
              onSelect: (_) {},
            ),
          ),
        ),
      );

      expect(find.byIcon(Icons.check), findsOneWidget);
    });

    testWidgets('shows FREE badge for free models', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ChatModelSuggestions(
              models: const [
                ChatModelInfo(id: 'm1', displayName: 'FreeModel'),
              ],
              selectedIndex: 0,
              currentModelId: 'm1',
              scrollController: ScrollController(),
              onSelect: (_) {},
            ),
          ),
        ),
      );

      expect(find.text('FREE'), findsOneWidget);
    });

    testWidgets('shows cost for priced models', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ChatModelSuggestions(
              models: const [
                ChatModelInfo(
                  id: 'm1',
                  displayName: ' pricey',
                  inputCostPerMillion: 2.5,
                ),
              ],
              selectedIndex: 0,
              currentModelId: 'm1',
              scrollController: ScrollController(),
              onSelect: (_) {},
            ),
          ),
        ),
      );

      expect(find.text('\$2.5'), findsOneWidget);
    });

    testWidgets('clamps selected index when out of range', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ChatModelSuggestions(
              models: const [
                ChatModelInfo(id: 'm1', displayName: 'A'),
              ],
              selectedIndex: 5,
              currentModelId: 'm1',
              scrollController: ScrollController(),
              onSelect: (_) {},
            ),
          ),
        ),
      );

      // Should render without throwing even though selectedIndex > length.
      expect(find.text('A'), findsOneWidget);
    });
  });
}
