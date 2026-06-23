/// Minimal status object returned by the platform-specific skills service.
class SetupSkillsStatus {
  const SetupSkillsStatus({
    required this.installed,
    required this.summary,
  });

  final bool installed;
  final String summary;
}
