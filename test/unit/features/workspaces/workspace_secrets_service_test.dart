import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yoloit/features/workspaces/data/workspace_secrets_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
  });

  test(
    'save preserves existing secret values when incoming values are empty',
    () async {
      final service = WorkspaceSecretsService.instance;

      await service.save('workspace-1', {'TOKEN': 'my_token', 'EMPTY': ''});
      await service.save('workspace-1', {'TOKEN': '', 'EMPTY': ''});

      final loaded = await service.load('workspace-1');
      expect(loaded['TOKEN'], 'my_token');
      expect(loaded['EMPTY'], '');
    },
  );

  test('delete removes workspace secrets', () async {
    final service = WorkspaceSecretsService.instance;

    await service.save('workspace-1', {'TOKEN': 'my_token'});
    await service.delete('workspace-1');

    expect(await service.load('workspace-1'), isEmpty);
  });
}
