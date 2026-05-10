import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:yoloit/core/platform/platform_launcher.dart';
import 'package:yoloit/core/session/session_prefs.dart';
import 'package:yoloit/core/theme/app_color_scheme.dart';
import 'package:yoloit/core/theme/app_colors.dart';
import 'package:yoloit/features/settings/data/setup_check_service.dart';

// ── Embedded (Settings panel) ─────────────────────────────────────────────────

/// Embedded version used inside the Settings panel (no dialog chrome).
class SetupGuideEmbedded extends StatefulWidget {
  const SetupGuideEmbedded({super.key});

  @override
  State<SetupGuideEmbedded> createState() => _SetupGuideEmbeddedState();
}

class _SetupGuideEmbeddedState extends State<SetupGuideEmbedded> {
  SetupCheckResult? _result;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _runChecks();
  }

  Future<void> _runChecks() async {
    setState(() => _loading = true);
    final result = await SetupCheckService.check();
    if (mounted) setState(() { _result = result; _loading = false; });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: _LoadingView());
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Body(result: _result!, onRecheck: _runChecks),
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Row(
            children: [
              Icon(
                _result!.allRequiredDepsOk ? Icons.check_circle_outline : Icons.warning_amber_rounded,
                size: 13,
                color: _result!.allRequiredDepsOk ? AppColors.neonGreen : AppColors.neonOrange,
              ),
              const SizedBox(width: 6),
              Text(
                _result!.allRequiredDepsOk
                    ? 'All required dependencies found'
                    : 'Some required dependencies are missing',
                style: TextStyle(
                  color: _result!.allRequiredDepsOk ? AppColors.neonGreen : AppColors.neonOrange,
                  fontSize: 11,
                ),
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: _loading ? null : _runChecks,
                icon: const Icon(Icons.refresh, size: 12),
                label: const Text('Re-check', style: TextStyle(fontSize: 11)),
                style: TextButton.styleFrom(foregroundColor: Theme.of(context).textTheme.bodySmall?.color),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ── Wizard dialog ─────────────────────────────────────────────────────────────

class SetupGuidePage extends StatefulWidget {
  const SetupGuidePage({super.key, this.isWizard = false});

  /// When true, shows "Get Started" button and marks setup as complete on dismiss.
  final bool isWizard;

  static Future<void> show(BuildContext context, {bool isWizard = false}) {
    return showDialog<void>(
      context: context,
      barrierDismissible: !isWizard,
      builder: (_) => SetupGuidePage(isWizard: isWizard),
    );
  }

  static Future<void> showIfFirstLaunch(BuildContext context) async {
    final done = await SessionPrefs.isSetupCompleted();
    if (!done && context.mounted) {
      await show(context, isWizard: true);
    }
  }

  @override
  State<SetupGuidePage> createState() => _SetupGuidePageState();
}

class _SetupGuidePageState extends State<SetupGuidePage> {
  SetupCheckResult? _result;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _runChecks();
  }

  Future<void> _runChecks() async {
    setState(() => _loading = true);
    final result = await SetupCheckService.check();
    if (mounted) setState(() { _result = result; _loading = false; });
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Dialog(
      backgroundColor: colors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: SizedBox(
        width: 600,
        height: 680,
        child: Column(
          children: [
            _Header(isWizard: widget.isWizard, onClose: widget.isWizard ? null : () => Navigator.pop(context)),
            const Divider(height: 1),
            Expanded(
              child: _loading
                  ? const Center(child: _LoadingView())
                  : _Body(result: _result!, onRecheck: _runChecks),
            ),
            const Divider(height: 1),
            _Footer(
              isWizard: widget.isWizard,
              result: _result,
              loading: _loading,
              onRecheck: _runChecks,
              onGetStarted: () async {
                await SessionPrefs.markSetupCompleted();
                if (context.mounted) Navigator.pop(context);
              },
            ),
          ],
        ),
      ),
    );
  }
}

// ── Header ────────────────────────────────────────────────────────────────────

class _Header extends StatelessWidget {
  const _Header({required this.isWizard, this.onClose});
  final bool isWizard;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Row(
        children: [
          Container(
            width: 40, height: 40,
            decoration: BoxDecoration(
              color: AppColors.neonBlue.withAlpha(20),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.checklist_rtl_rounded, color: AppColors.neonBlue, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Welcome to YoLoIT 👋',
                    style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontSize: 16, fontWeight: FontWeight.w600)),
                Text('Check dependencies and configure AI agents',
                    style: TextStyle(color: Theme.of(context).textTheme.bodySmall?.color ?? Theme.of(context).colorScheme.onSurface, fontSize: 11)),
              ],
            ),
          ),
          if (onClose != null)
            IconButton(
              icon: const Icon(Icons.close, size: 16),
              onPressed: onClose,
              color: Theme.of(context).textTheme.bodySmall?.color ?? Theme.of(context).colorScheme.onSurface,
              splashRadius: 16,
            ),
        ],
      ),
    );
  }
}

// ── Loading ───────────────────────────────────────────────────────────────────

class _LoadingView extends StatelessWidget {
  const _LoadingView();

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.neonBlue)),
        const SizedBox(height: 12),
        Text('Checking your environment...', style: TextStyle(color: Theme.of(context).textTheme.bodySmall?.color ?? Theme.of(context).colorScheme.onSurface, fontSize: 12)),
      ],
    );
  }
}

// ── Body ──────────────────────────────────────────────────────────────────────

class _Body extends StatelessWidget {
  const _Body({required this.result, required this.onRecheck});
  final SetupCheckResult result;
  final VoidCallback onRecheck;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (Platform.isMacOS) ...[
            const _SectionTitle(
              icon: Icons.folder_open_outlined,
              label: 'macOS Permissions',
              subtitle: 'Allow access to folders on your Mac',
            ),
            const SizedBox(height: 10),
            const _MacOsPermissionsCard(),
            const SizedBox(height: 28),
          ],

          const _SectionTitle(
            icon: Icons.settings_suggest_outlined,
            label: 'System Dependencies',
            subtitle: 'Required for core functionality',
          ),
          const SizedBox(height: 10),
          ...result.deps.map((dep) => _DependencyCard(dep: dep, onInstalled: onRecheck)),
          const SizedBox(height: 28),

          _SectionTitle(
            icon: Icons.smart_toy_outlined,
            label: 'AI Agents',
            subtitle: result.anyAgentAvailable
                ? 'Detected on your system'
                : 'No agents detected — install at least one to get started',
            subtitleColor: result.anyAgentAvailable ? null : AppColors.neonOrange,
          ),
          const SizedBox(height: 10),
          ...result.agents.map((agent) => _DependencyCard(dep: agent, onInstalled: onRecheck)),
        ],
      ),
    );
  }
}

// ── macOS Permissions card ────────────────────────────────────────────────────

enum _PermissionStatus { unknown, granted, denied }

class _MacOsPermissionsCard extends StatefulWidget {
  const _MacOsPermissionsCard();

  @override
  State<_MacOsPermissionsCard> createState() => _MacOsPermissionsCardState();
}

class _MacOsPermissionsCardState extends State<_MacOsPermissionsCard> {
  _PermissionStatus _status = _PermissionStatus.unknown;
  bool _checking = false;

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    setState(() => _checking = true);
    final granted = await _canAccessDocuments();
    if (mounted) {
      setState(() {
        _status = granted ? _PermissionStatus.granted : _PermissionStatus.denied;
        _checking = false;
      });
    }
  }

  /// Tries to list ~/Documents without triggering a TCC prompt.
  static Future<bool> _canAccessDocuments() async {
    try {
      final home = Platform.environment['HOME'] ?? '';
      final docs = Directory('$home/Documents');
      await docs.list().first;
      return true;
    } on PathAccessException {
      return false;
    } catch (_) {
      return true;
    }
  }

  Future<void> _openPrivacySettings() async {
    await PlatformLauncher.instance.openUrl(
      'x-apple.systempreferences:com.apple.preference.security?Privacy_FilesAndFolders',
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    final Color statusColor;
    final IconData statusIcon;

    if (_checking) {
      statusColor = AppColors.neonBlue;
      statusIcon = Icons.hourglass_top_rounded;
    } else if (_status == _PermissionStatus.granted) {
      statusColor = AppColors.neonGreen;
      statusIcon = Icons.check_circle_outline;
    } else {
      statusColor = AppColors.neonOrange;
      statusIcon = Icons.warning_amber_rounded;
    }

    final borderColor = _status == _PermissionStatus.granted
        ? AppColors.neonGreen.withAlpha(60)
        : _checking
            ? AppColors.neonBlue.withAlpha(60)
            : AppColors.neonOrange.withAlpha(60);

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: colors.surfaceElevated,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: borderColor),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            if (_checking)
              const SizedBox(
                width: 14, height: 14,
                child: CircularProgressIndicator(strokeWidth: 1.5, color: AppColors.neonBlue),
              )
            else
              Icon(statusIcon, size: 14, color: statusColor),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Folder Access',
                    style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontSize: 12, fontWeight: FontWeight.w500),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    'Allow YoLoIT in System Settings → Privacy & Security → Files and Folders',
                    style: TextStyle(color: Theme.of(context).textTheme.bodySmall?.color ?? Theme.of(context).colorScheme.onSurface, fontSize: 10),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            if (_checking)
              const SizedBox.shrink()
            else ...[
              if (_status == _PermissionStatus.granted)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.neonGreen.withAlpha(20),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text('Granted', style: TextStyle(color: AppColors.neonGreen, fontSize: 9, fontWeight: FontWeight.w600)),
                )
              else ...[
                GestureDetector(
                  onTap: _check,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: (Theme.of(context).textTheme.bodySmall?.color ?? Theme.of(context).colorScheme.onSurface).withAlpha(60)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.refresh, size: 9, color: Theme.of(context).textTheme.bodySmall?.color ?? Theme.of(context).colorScheme.onSurface),
                        const SizedBox(width: 3),
                        Text('Re-check', style: TextStyle(color: Theme.of(context).textTheme.bodySmall?.color ?? Theme.of(context).colorScheme.onSurface, fontSize: 9)),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 4),
              ],
              GestureDetector(
                onTap: _openPrivacySettings,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.neonBlue.withAlpha(20),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: AppColors.neonBlue.withAlpha(60)),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.security_outlined, size: 10, color: AppColors.neonBlue),
                      SizedBox(width: 4),
                      Text('Privacy Settings', style: TextStyle(color: AppColors.neonBlue, fontSize: 9, fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ── Section title ─────────────────────────────────────────────────────────────

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.icon, required this.label, required this.subtitle, this.subtitleColor});
  final IconData icon;
  final String label;
  final String subtitle;
  final Color? subtitleColor;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 14, color: AppColors.neonBlue),
        const SizedBox(width: 8),
        Text(label, style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontSize: 12, fontWeight: FontWeight.w600)),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            subtitle,
            style: TextStyle(color: subtitleColor ?? Theme.of(context).textTheme.bodySmall?.color ?? Theme.of(context).colorScheme.onSurface, fontSize: 10),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

// ── Install phase ─────────────────────────────────────────────────────────────

enum _Phase { idle, installing, done, failed }

// ── Dependency card (stateful — handles install + progress) ───────────────────

class _DependencyCard extends StatefulWidget {
  const _DependencyCard({required this.dep, required this.onInstalled});
  final DependencyStatus dep;
  final VoidCallback onInstalled;

  @override
  State<_DependencyCard> createState() => _DependencyCardState();
}

class _DependencyCardState extends State<_DependencyCard> {
  _Phase _phase = _Phase.idle;
  final List<String> _output = [];
  bool _showOutput = false;
  StreamSubscription<String>? _sub;
  final _scrollController = ScrollController();

  @override
  void dispose() {
    _sub?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _install() async {
    final action = widget.dep.installAction;
    if (action == null) return;

    setState(() {
      _phase = _Phase.installing;
      _output.clear();
      _showOutput = true;
    });

    _sub = SetupCheckService.install(action).listen(
      (line) {
        if (mounted) {
          setState(() => _output.add(line));
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (_scrollController.hasClients) {
              _scrollController.animateTo(
                _scrollController.position.maxScrollExtent,
                duration: const Duration(milliseconds: 150),
                curve: Curves.easeOut,
              );
            }
          });
        }
      },
      onDone: () {
        if (!mounted) return;
        final success = _output.any((l) => l.contains('✅'));
        setState(() => _phase = success ? _Phase.done : _Phase.failed);
        if (success) {
          Future.delayed(const Duration(milliseconds: 800), widget.onInstalled);
        }
      },
      onError: (Object e) {
        if (mounted) setState(() { _output.add('❌ $e'); _phase = _Phase.failed; });
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final dep = widget.dep;
    final ok = dep.isAvailable;

    Color statusColor;
    IconData statusIcon;
    if (ok) {
      statusColor = AppColors.neonGreen;
      statusIcon = Icons.check_circle_outline;
    } else if (_phase == _Phase.installing) {
      statusColor = AppColors.neonBlue;
      statusIcon = Icons.hourglass_top_rounded;
    } else if (_phase == _Phase.done) {
      statusColor = AppColors.neonGreen;
      statusIcon = Icons.check_circle_outline;
    } else if (_phase == _Phase.failed) {
      statusColor = Colors.red.shade400;
      statusIcon = Icons.error_outline;
    } else {
      statusColor = dep.isRequired ? Colors.red.shade400 : AppColors.neonOrange;
      statusIcon = Icons.warning_amber_rounded;
    }

    final borderColor = ok || _phase == _Phase.done
        ? AppColors.neonGreen.withAlpha(60)
        : _phase == _Phase.installing
            ? AppColors.neonBlue.withAlpha(60)
            : _phase == _Phase.failed
                ? Colors.red.withAlpha(60)
                : dep.isRequired
                    ? Colors.red.withAlpha(40)
                    : colors.border;

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: colors.surfaceElevated,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        children: [
          // ── Main row ───────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                // Status icon / spinner
                if (_phase == _Phase.installing)
                  const SizedBox(
                    width: 14, height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 1.5,
                      color: AppColors.neonBlue,
                    ),
                  )
                else
                  Icon(statusIcon, size: 14, color: statusColor),

                const SizedBox(width: 10),

                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(dep.name,
                              style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontSize: 12, fontWeight: FontWeight.w500)),
                          if (dep.isRequired)
                            Container(
                              margin: const EdgeInsets.only(left: 6),
                              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                              decoration: BoxDecoration(
                                color: Colors.red.withAlpha(25),
                                borderRadius: BorderRadius.circular(3),
                              ),
                              child: const Text('required', style: TextStyle(color: Colors.redAccent, fontSize: 8)),
                            ),
                          if ((ok || _phase == _Phase.done) && dep.version != null) ...[
                            const SizedBox(width: 8),
                            Text(dep.version!, style: TextStyle(color: Theme.of(context).textTheme.bodySmall?.color ?? Theme.of(context).colorScheme.onSurface, fontSize: 10)),
                          ],
                        ],
                      ),
                      const SizedBox(height: 1),
                      Text(dep.description, style: TextStyle(color: Theme.of(context).textTheme.bodySmall?.color ?? Theme.of(context).colorScheme.onSurface, fontSize: 10)),
                    ],
                  ),
                ),

                // Action area
                if (ok || _phase == _Phase.done)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppColors.neonGreen.withAlpha(20),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text('Available', style: TextStyle(color: AppColors.neonGreen, fontSize: 9, fontWeight: FontWeight.w600)),
                  )
                else if (_phase == _Phase.installing)
                  _outputToggleButton(_showOutput)
                else if (!ok) ...[
                  if (dep.installAction != null) ...[
                    _InstallButton(onPressed: _install),
                    const SizedBox(width: 4),
                  ],
                  _CopyButton(hint: dep.installHint),
                ],
              ],
            ),
          ),

          // ── Output log ─────────────────────────────────────────────────
          if (_showOutput && _output.isNotEmpty)
            _OutputLog(
              output: _output,
              phase: _phase,
              scrollController: _scrollController,
              onToggle: () => setState(() => _showOutput = !_showOutput),
            ),

          // ── Retry / dismiss ────────────────────────────────────────────
          if (_phase == _Phase.failed)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => setState(() { _phase = _Phase.idle; _output.clear(); _showOutput = false; }),
                    child: Text('Dismiss', style: TextStyle(fontSize: 10, color: Theme.of(context).textTheme.bodySmall?.color ?? Theme.of(context).colorScheme.onSurface)),
                  ),
                  const SizedBox(width: 4),
                  TextButton(
                    onPressed: _install,
                    child: const Text('Retry', style: TextStyle(fontSize: 10, color: AppColors.neonBlue)),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _outputToggleButton(bool expanded) {
    return GestureDetector(
      onTap: () => setState(() => _showOutput = !_showOutput),
      child: Text(
        expanded ? 'Hide log ▲' : 'Show log ▼',
        style: TextStyle(color: Theme.of(context).textTheme.bodySmall?.color ?? Theme.of(context).colorScheme.onSurface, fontSize: 9),
      ),
    );
  }
}

// ── Output log ────────────────────────────────────────────────────────────────

class _OutputLog extends StatelessWidget {
  const _OutputLog({
    required this.output,
    required this.phase,
    required this.scrollController,
    required this.onToggle,
  });
  final List<String> output;
  final _Phase phase;
  final ScrollController scrollController;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      padding: const EdgeInsets.all(10),
      constraints: const BoxConstraints(maxHeight: 180),
      decoration: BoxDecoration(
        color: colors.background,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                phase == _Phase.installing ? 'Installing...' : 'Output',
                style: TextStyle(color: Theme.of(context).textTheme.bodySmall?.color ?? Theme.of(context).colorScheme.onSurface, fontSize: 9, fontWeight: FontWeight.w600),
              ),
              const Spacer(),
              GestureDetector(
                onTap: onToggle,
                child: Text('▲ hide', style: TextStyle(color: Theme.of(context).textTheme.bodySmall?.color ?? Theme.of(context).colorScheme.onSurface, fontSize: 9)),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Expanded(
            child: ListView.builder(
              controller: scrollController,
              itemCount: output.length,
              itemBuilder: (_, i) {
                final line = output[i];
                final isSuccess = line.contains('✅');
                final isError = line.contains('❌');
                return Text(
                  line,
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 9,
                    color: isSuccess
                        ? AppColors.neonGreen
                        : isError
                            ? Colors.red.shade300
                            : Theme.of(context).textTheme.bodyMedium?.color ?? Theme.of(context).colorScheme.onSurface,
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ── Install button ────────────────────────────────────────────────────────────

class _InstallButton extends StatelessWidget {
  const _InstallButton({required this.onPressed});
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onPressed,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: AppColors.neonBlue.withAlpha(25),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: AppColors.neonBlue.withAlpha(80)),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.download_rounded, size: 10, color: AppColors.neonBlue),
            SizedBox(width: 4),
            Text('Install', style: TextStyle(color: AppColors.neonBlue, fontSize: 9, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}

// ── Copy button ───────────────────────────────────────────────────────────────

class _CopyButton extends StatefulWidget {
  const _CopyButton({required this.hint});
  final String hint;

  @override
  State<_CopyButton> createState() => _CopyButtonState();
}

class _CopyButtonState extends State<_CopyButton> {
  bool _copied = false;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: widget.hint,
      child: GestureDetector(
        onTap: () async {
          await Clipboard.setData(ClipboardData(text: widget.hint));
          setState(() => _copied = true);
          await Future<void>.delayed(const Duration(seconds: 2));
          if (mounted) setState(() => _copied = false);
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: (Theme.of(context).textTheme.bodySmall?.color ?? Theme.of(context).colorScheme.onSurface).withAlpha(60)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                _copied ? Icons.check : Icons.copy_outlined,
                size: 10,
                color: Theme.of(context).textTheme.bodySmall?.color ?? Theme.of(context).colorScheme.onSurface,
              ),
              const SizedBox(width: 3),
              Text(
                _copied ? 'Copied' : 'Copy',
                style: TextStyle(color: Theme.of(context).textTheme.bodySmall?.color ?? Theme.of(context).colorScheme.onSurface, fontSize: 9),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Footer ────────────────────────────────────────────────────────────────────

class _Footer extends StatelessWidget {
  const _Footer({
    required this.isWizard,
    required this.result,
    required this.loading,
    required this.onRecheck,
    required this.onGetStarted,
  });
  final bool isWizard;
  final SetupCheckResult? result;
  final bool loading;
  final VoidCallback onRecheck;
  final VoidCallback onGetStarted;

  @override
  Widget build(BuildContext context) {
    final ok = result?.allRequiredDepsOk ?? false;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      child: Row(
        children: [
          if (!loading && result != null) ...[
            Icon(
              ok ? Icons.check_circle_outline : Icons.warning_amber_rounded,
              size: 13,
              color: ok ? AppColors.neonGreen : AppColors.neonOrange,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                ok ? 'All required dependencies found' : 'Some required dependencies are missing',
                style: TextStyle(color: ok ? AppColors.neonGreen : AppColors.neonOrange, fontSize: 11),
              ),
            ),
          ] else
            const Spacer(),
          TextButton.icon(
            onPressed: loading ? null : onRecheck,
            icon: const Icon(Icons.refresh, size: 12),
            label: const Text('Re-check', style: TextStyle(fontSize: 11)),
            style: TextButton.styleFrom(foregroundColor: Theme.of(context).textTheme.bodySmall?.color),
          ),
          if (isWizard) ...[
            const SizedBox(width: 8),
            ElevatedButton(
              onPressed: onGetStarted,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.neonBlue,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
              ),
              child: const Text('Get Started →'),
            ),
          ],
        ],
      ),
    );
  }
}
