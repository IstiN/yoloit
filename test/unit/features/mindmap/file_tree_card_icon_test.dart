import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yoloit/features/mindmap/nodes/presentation/file_tree_card.dart';

void main() {
  test('tree row preserves every file icon classification', () {
    void expectFiles(List<String> extensions, IconData icon) {
      for (final extension in extensions) {
        expect(
          debugTreeRowIconForFile('sample.$extension'),
          icon,
          reason: extension,
        );
      }
    }

    expectFiles(['dart', 'py'], Icons.code);
    expectFiles(['yaml', 'yml'], Icons.settings);
    expectFiles(['json'], Icons.data_object);
    expectFiles(['md'], Icons.description);
    expectFiles(['ts', 'tsx', 'js', 'jsx'], Icons.javascript);
    expectFiles(['png', 'jpg', 'jpeg', 'gif', 'svg'], Icons.image);

    // Extension lookup is case-insensitive.
    expect(debugTreeRowIconForFile('SAMPLE.DART'), Icons.code);
    expect(debugTreeRowIconForFile('SAMPLE.PNG'), Icons.image);

    // Names without an extension fall back to the generic file icon.
    for (final name in ['README', '.gitignore', 'file.unknown']) {
      expect(
        debugTreeRowIconForFile(name),
        Icons.insert_drive_file_outlined,
        reason: name,
      );
    }
  });
}
