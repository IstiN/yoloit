import 'dart:async';

import 'package:yoloit/core/setup/setup_skills_status.dart';

/// VM/headless stub: global skills are not available outside the Flutter app.
Stream<String> installOrUpdateSkills() async* {}

Future<SetupSkillsStatus> checkSkills() async {
  return const SetupSkillsStatus(
    installed: false,
    summary: 'Global skills not available in headless mode',
  );
}
