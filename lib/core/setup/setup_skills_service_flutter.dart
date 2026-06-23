import 'dart:async';

import 'package:yoloit/core/setup/setup_skills_status.dart';
import 'package:yoloit/core/skills/yoloit_global_skills_service.dart';

/// Flutter implementation that delegates to [YoloitGlobalSkillsService].
Stream<String> installOrUpdateSkills() {
  return YoloitGlobalSkillsService.instance.installOrUpdate();
}

Future<SetupSkillsStatus> checkSkills() async {
  final status = await YoloitGlobalSkillsService.instance.check();
  return SetupSkillsStatus(
    installed: status.installed,
    summary: status.summary,
  );
}
