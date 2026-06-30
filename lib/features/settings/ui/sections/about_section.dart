import 'package:flutter/material.dart';
import 'package:yoloit/core/session/session_prefs.dart';
import 'package:yoloit/core/theme/app_color_scheme.dart';
import 'package:yoloit/features/updates/data/update_service.dart';

class AboutSection extends StatefulWidget {
  const AboutSection({super.key});

  @override
  State<AboutSection> createState() => AboutSectionState();
}

class AboutSectionState extends State<AboutSection> {
  bool _checking = false;
  bool _autoCheck = true;
  UpdateInfo? _updateInfo;
  String? _upToDateMsg;
  String? _checkError;
  bool _installing = false;
  double? _installProgress;
  String _installStatus = '';

  @override
  void initState() {
    super.initState();
    SessionPrefs.isAutoUpdateCheckEnabled().then((v) {
      if (mounted) setState(() => _autoCheck = v);
    });
    // Eagerly load the real version from Info.plist so the UI shows it.
    UpdateService.getAppVersion().then((_) {
      if (mounted) setState(() {});
    });
  }

  Future<void> _checkNow() async {
    setState(() {
      _checking = true;
      _upToDateMsg = null;
      _checkError = null;
      _updateInfo = null;
    });
    final result = await UpdateService.checkForUpdate(force: true);
    if (!mounted) return;
    setState(() {
      _checking = false;
      switch (result.status) {
        case UpdateCheckStatus.available:
          _updateInfo = result.info;
        case UpdateCheckStatus.upToDate:
          _upToDateMsg =
              'You are on the latest version (${UpdateService.currentVersion}).';
        case UpdateCheckStatus.skipped:
          _upToDateMsg =
              'v${result.skippedVersion} is available but was skipped. '
              'Clear skip in prefs or wait for a newer release.';
        case UpdateCheckStatus.failed:
          _checkError = result.errorMessage;
      }
    });
  }

  Future<void> _installUpdate(UpdateInfo info) async {
    setState(() {
      _installing = true;
      _installProgress = null;
      _installStatus = 'Preparing…';
    });
    try {
      await UpdateService.downloadAndInstall(
        info,
        onProgress: (progress, status) {
          if (mounted) {
            setState(() {
              _installProgress = progress;
              _installStatus = status;
            });
          }
        },
      );
      // If we get here without exit(), the installer opened browser fallback.
    } catch (e) {
      if (mounted) {
        final colors = context.appColors;
        setState(() {
          _installing = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Update failed: $e'),
            backgroundColor: colors.accentRed,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── App info ────────────────────────────────────────────────────────
        _card(colors, child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'YoLoIT — AI Orchestrator',
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.onSurface,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Text(
                              'v${UpdateService.currentVersion}',
                              style: TextStyle(
                                color: context.appColors.textMuted,
                                fontSize: 11,
                              ),
                            ),
                            if (UpdateService.isDevBuild) ...[
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 5,
                                  vertical: 1,
                                ),
                                decoration: BoxDecoration(
                                  color: colors.accentOrange.withAlpha(30),
                                  borderRadius: BorderRadius.circular(3),
                                  border: Border.all(
                                    color: colors.accentOrange.withAlpha(80),
                                  ),
                                ),
                                child: Text(
                                  'DEV',
                                  style: TextStyle(
                                    color: colors.accentOrange,
                                    fontSize: 8,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'A Flutter desktop app for orchestrating AI CLI tools (GitHub Copilot, Claude Code) with embedded PTY terminals and git workspace management.',
                style: TextStyle(
                  color: context.appColors.textMuted,
                  fontSize: 12,
                  height: 1.6,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Platform: macOS (primary) • Windows (coming soon)',
                style: TextStyle(
                  color: context.appColors.textMuted,
                  fontSize: 11,
                ),
              ),
            ],
          )),
        const SizedBox(height: 16),

        // ── Update section ──────────────────────────────────────────────────
        _card(colors, child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Updates',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 12),

              // Auto-check toggle
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Auto-check for updates',
                      style: TextStyle(
                        color:
                            Theme.of(context).textTheme.bodyMedium?.color ??
                            Theme.of(context).colorScheme.onSurface,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  Switch(
                    value: _autoCheck,
                    activeThumbColor: colors.accentBlue,
                    onChanged: (v) {
                      setState(() => _autoCheck = v);
                      SessionPrefs.saveAutoUpdateCheckEnabled(v);
                    },
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                UpdateService.isDevBuild
                    ? 'DEV build: auto-check is off. Use “Check for Updates” manually.'
                    : 'Checks GitHub releases once per day in release builds.',
                style: TextStyle(
                  color: context.appColors.textMuted,
                  fontSize: 10,
                ),
              ),

              const SizedBox(height: 16),

              // Check now button
              Row(
                children: [
                  ElevatedButton.icon(
                    onPressed: _checking ? null : _checkNow,
                    icon:
                        _checking
                            ? const SizedBox(
                              width: 12,
                              height: 12,
                              child: CircularProgressIndicator(
                                strokeWidth: 1.5,
                                color: Colors.white,
                              ),
                            )
                            : const Icon(Icons.search, size: 14),
                    label: Text(
                      _checking ? 'Checking...' : 'Check for Updates',
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: colors.surfaceElevated,
                      foregroundColor: Theme.of(context).colorScheme.onSurface,
                      textStyle: const TextStyle(fontSize: 11),
                      side: BorderSide(color: colors.border),
                      elevation: 0,
                    ),
                  ),
                ],
              ),

              // Result
              if (_checkError != null) ...[
                const SizedBox(height: 10),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.error_outline,
                      size: 14,
                      color: colors.accentRed,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        _checkError!,
                        style: TextStyle(color: colors.accentRed, fontSize: 11),
                      ),
                    ),
                  ],
                ),
              ],

              if (_upToDateMsg != null) ...[
                const SizedBox(height: 10),
                Row(
                  children: [
                    Icon(
                      Icons.check_circle_outline,
                      size: 14,
                      color: colors.accentGreen,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      _upToDateMsg!,
                      style: TextStyle(color: colors.accentGreen, fontSize: 11),
                    ),
                  ],
                ),
              ],

              if (_updateInfo != null) ...[
                const SizedBox(height: 10),
                if (_installing) ...[
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _installStatus,
                        style: TextStyle(
                          color:
                              Theme.of(context).textTheme.bodyMedium?.color ??
                              Theme.of(context).colorScheme.onSurface,
                          fontSize: 11,
                        ),
                      ),
                      const SizedBox(height: 6),
                      LinearProgressIndicator(
                        value: _installProgress,
                        backgroundColor: colors.accentBlue.withAlpha(30),
                        color: colors.accentBlue,
                        minHeight: 3,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'App will restart automatically after install.',
                        style: TextStyle(
                          color: context.appColors.textMuted,
                          fontSize: 10,
                        ),
                      ),
                    ],
                  ),
                ] else
                  UpdateAvailableCard(
                    info: _updateInfo!,
                    onDownload: () => _installUpdate(_updateInfo!),
                    onSkip: () async {
                      await UpdateService.skipVersion(_updateInfo!.version);
                      if (mounted) setState(() => _updateInfo = null);
                    },
                  ),
              ],
            ],
          )),
      ],
    );
  }

  Widget _card(AppColorScheme colors, {required Widget child}) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: colors.background,
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: colors.border),
    ),
    child: child,
  );
}

class UpdateAvailableCard extends StatelessWidget {
  const UpdateAvailableCard({
    super.key,
    required this.info,
    required this.onDownload,
    required this.onSkip,
  });

  final UpdateInfo info;
  final VoidCallback onDownload;
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.accentBlue.withAlpha(15),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: colors.accentBlue.withAlpha(60)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.system_update_alt_rounded,
                size: 14,
                color: colors.accentBlue,
              ),
              const SizedBox(width: 8),
              Text(
                '${info.tagName} is available!',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          if (info.releaseNotes.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              info.releaseNotes.length > 200
                  ? '${info.releaseNotes.substring(0, 200)}...'
                  : info.releaseNotes,
              style: TextStyle(
                color: context.appColors.textMuted,
                fontSize: 10,
                height: 1.5,
              ),
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              ElevatedButton.icon(
                onPressed: onDownload,
                icon: const Icon(Icons.download_rounded, size: 14),
                label: const Text('Download'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: colors.accentBlue,
                  foregroundColor: Colors.white,
                  textStyle: const TextStyle(fontSize: 11),
                  elevation: 0,
                ),
              ),
              const SizedBox(width: 8),
              TextButton(
                onPressed: onSkip,
                child: Text(
                  'Skip this version',
                  style: TextStyle(
                    fontSize: 10,
                    color: context.appColors.textMuted,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
