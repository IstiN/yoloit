import 'package:yoloit/features/updates/data/update_service.dart';

enum UpdateCheckStatus { available, upToDate, skipped, failed }

/// Result of [UpdateService.checkForUpdate].
class UpdateCheckResult {
  const UpdateCheckResult._({
    required this.status,
    this.info,
    this.errorMessage,
    this.skippedVersion,
  });

  final UpdateCheckStatus status;
  final UpdateInfo? info;
  final String? errorMessage;
  final String? skippedVersion;

  factory UpdateCheckResult.available(UpdateInfo info) => UpdateCheckResult._(
        status: UpdateCheckStatus.available,
        info: info,
      );

  factory UpdateCheckResult.upToDate() => const UpdateCheckResult._(
        status: UpdateCheckStatus.upToDate,
      );

  factory UpdateCheckResult.skipped(String version) => UpdateCheckResult._(
        status: UpdateCheckStatus.skipped,
        skippedVersion: version,
      );

  factory UpdateCheckResult.failed(String message) => UpdateCheckResult._(
        status: UpdateCheckStatus.failed,
        errorMessage: message,
      );
}
