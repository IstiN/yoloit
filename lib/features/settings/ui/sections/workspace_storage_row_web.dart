import 'package:flutter/material.dart';

/// Web placeholder for [WorkspaceStorageRow].
///
/// Workspace file storage path selection is a desktop-only feature, so this row
/// is hidden on the web.
class WorkspaceStorageRow extends StatelessWidget {
  const WorkspaceStorageRow({super.key});

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
