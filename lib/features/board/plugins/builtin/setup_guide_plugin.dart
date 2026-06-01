import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:yoloit/core/remote/yoloit_remote_client.dart';
import 'package:yoloit/core/setup/setup_catalog.dart';
import 'package:yoloit/core/theme/app_color_scheme.dart';
import 'package:yoloit/features/board/model/board_models.dart';
import 'package:yoloit/features/board/plugins/board_plugin.dart';

class SetupGuidePlugin extends BoardPanelPlugin {
  const SetupGuidePlugin();

  static const String kTypeId = 'board.setup_guide';

  @override
  String get typeId => kTypeId;

  @override
  String get displayName => 'Setup Guide';

  @override
  IconData get icon => Icons.install_desktop_outlined;

  @override
  Color get accentColor => Colors.lightBlueAccent;

  @override
  Size get defaultSize => const Size(560, 520);

  @override
  Map<String, dynamic> get initialState => const {
    'selectedPackageIds': <String>['git', 'tmux', 'codex'],
  };

  @override
  Widget buildContent(
    BuildContext context,
    BoardPanelInstance panel,
    BoardPanelRenderContext renderContext,
  ) {
    return SetupGuidePanel(panel: panel, renderContext: renderContext);
  }
}

class SetupGuidePanel extends StatefulWidget {
  const SetupGuidePanel({
    super.key,
    required this.panel,
    required this.renderContext,
    this.initialSnapshot,
  });

  final BoardPanelInstance panel;
  final BoardPanelRenderContext renderContext;
  final SetupCheckSnapshot? initialSnapshot;

  @override
  State<SetupGuidePanel> createState() => _SetupGuidePanelState();
}

class _SetupGuidePanelState extends State<SetupGuidePanel> {
  SetupCheckSnapshot? _snapshot;
  final List<String> _log = <String>[];
  final ScrollController _logScroll = ScrollController();
  Timer? _pollTimer;
  bool _loading = true;
  bool _installing = false;
  String? _error;
  String? _remoteRunId;
  String? _lastScript;
  late Set<String> _selectedIds;

  bool get _isRemote => widget.renderContext.remoteInfo != null;

  @override
  void initState() {
    super.initState();
    _selectedIds = _readSelectedIds();
    final initial = widget.initialSnapshot;
    if (initial == null) {
      unawaited(_refresh());
    } else {
      _snapshot = initial;
      _loading = false;
    }
  }

  @override
  void didUpdateWidget(covariant SetupGuidePanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.panel.id != widget.panel.id ||
        oldWidget.panel.state != widget.panel.state) {
      _selectedIds = _readSelectedIds();
    }
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _logScroll.dispose();
    super.dispose();
  }

  Set<String> _readSelectedIds() {
    final raw = widget.panel.state['selectedPackageIds'];
    if (raw is List) {
      final ids = raw.map((value) => value.toString()).toSet();
      if (ids.isNotEmpty) return ids;
    }
    return <String>{'git', 'tmux', 'codex'};
  }

  Future<void> _refresh() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final remote = widget.renderContext.remoteInfo;
      final snapshot =
          remote == null
              ? await SetupCatalog.check()
              : await YoloitRemoteClient(
                baseUrl: remote.url,
                token: remote.token,
              ).setupCheck();
      if (!mounted) return;
      setState(() {
        _snapshot = snapshot;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
        _loading = false;
      });
    }
  }

  void _toggle(String id, bool selected) {
    setState(() {
      if (selected) {
        _selectedIds.add(id);
      } else {
        _selectedIds.remove(id);
      }
    });
    widget.renderContext.onUpdateState({
      ...widget.panel.state,
      'selectedPackageIds': _selectedIds.toList()..sort(),
    });
  }

  Future<void> _installSelected() async {
    final snapshot = _snapshot;
    if (snapshot == null || _selectedIds.isEmpty) return;
    setState(() {
      _installing = true;
      _error = null;
      _log
        ..clear()
        ..add(
          'Target: ${snapshot.runtime.osLabel} ${snapshot.runtime.versionLabel}'
              .trim(),
        );
    });
    try {
      final remote = widget.renderContext.remoteInfo;
      if (remote == null) {
        final script = SetupCatalog.installScript(
          _selectedIds,
          snapshot.runtime.os,
        );
        if (script.trim().isEmpty) {
          throw StateError(
            'No install command for selected packages on this OS.',
          );
        }
        _lastScript = script;
        _appendLog('\$ $script');
        await for (final line in runSetupInstallScript(script)) {
          if (!mounted) return;
          _appendLog(line);
        }
        await _refresh();
      } else {
        final client = YoloitRemoteClient(
          baseUrl: remote.url,
          token: remote.token,
        );
        final run = await client.startSetupInstall(
          _selectedIds.toList()..sort(),
        );
        _remoteRunId = run.id;
        _lastScript = run.script;
        _appendLog('\$ ${run.script}');
        _pollRemoteInstall(client, run.id);
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _installing = false;
        _error = error.toString();
      });
    }
  }

  void _pollRemoteInstall(YoloitRemoteClient client, String runId) {
    _pollTimer?.cancel();
    var seen = 0;
    _pollTimer = Timer.periodic(const Duration(seconds: 1), (timer) async {
      try {
        final log = await client.setupInstallLog(runId);
        final next = log.lines.skip(seen).toList();
        seen = log.lines.length;
        if (next.isNotEmpty && mounted) {
          setState(() => _log.addAll(next));
          _scrollLog();
        }
        if (!log.running) {
          timer.cancel();
          if (!mounted) return;
          setState(() => _installing = false);
          await _refresh();
        }
      } catch (error) {
        timer.cancel();
        if (!mounted) return;
        setState(() {
          _installing = false;
          _error = error.toString();
        });
      }
    });
  }

  void _appendLog(String line) {
    setState(() => _log.add(line));
    _scrollLog();
  }

  void _scrollLog() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_logScroll.hasClients) return;
      _logScroll.animateTo(
        _logScroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOut,
      );
    });
  }

  String? _scriptFor(SetupCheckSnapshot snapshot) {
    final commands =
        snapshot.packages
            .where((pkg) => _selectedIds.contains(pkg.id))
            .map((pkg) => pkg.installAction?.command.trim() ?? '')
            .where((command) => command.isNotEmpty)
            .toList();
    if (commands.isEmpty) return null;
    return _lastScript ?? SetupCatalog.installBatchScript(commands);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    if (_loading) {
      return Center(
        child: CircularProgressIndicator(
          color: colors.accentBlue,
          strokeWidth: 2,
        ),
      );
    }
    final snapshot = _snapshot;
    if (snapshot == null) {
      return _ErrorView(
        error: _error ?? 'Setup check failed',
        onRetry: _refresh,
      );
    }
    return Container(
      color: colors.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SetupHeader(
            snapshot: snapshot,
            isRemote: _isRemote,
            installing: _installing,
            selectedCount: _selectedIds.length,
            onRefresh: _refresh,
            onInstall:
                _selectedIds.isEmpty || _installing ? null : _installSelected,
            installScript: _scriptFor(snapshot),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
              child: Text(
                _error!,
                style: TextStyle(color: Colors.red.shade300, fontSize: 11),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
              children: [
                _Section(
                  title: 'System',
                  packages:
                      snapshot.packages
                          .where(
                            (pkg) =>
                                pkg.category == SetupPackageCategory.system,
                          )
                          .toList(),
                  selectedIds: _selectedIds,
                  onToggle: _toggle,
                ),
                _Section(
                  title: 'AI agents',
                  packages:
                      snapshot.packages
                          .where(
                            (pkg) =>
                                pkg.category == SetupPackageCategory.agents,
                          )
                          .toList(),
                  selectedIds: _selectedIds,
                  onToggle: _toggle,
                ),
                _Section(
                  title: 'Optional',
                  packages:
                      snapshot.packages
                          .where(
                            (pkg) =>
                                pkg.category == SetupPackageCategory.optional,
                          )
                          .toList(),
                  selectedIds: _selectedIds,
                  onToggle: _toggle,
                ),
                if (_log.isNotEmpty)
                  _InstallLog(lines: _log, controller: _logScroll),
                if (_remoteRunId != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      'Run: $_remoteRunId',
                      style: TextStyle(color: colors.textMuted, fontSize: 10),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SetupHeader extends StatefulWidget {
  const _SetupHeader({
    required this.snapshot,
    required this.isRemote,
    required this.installing,
    required this.selectedCount,
    required this.onRefresh,
    required this.onInstall,
    required this.installScript,
  });

  final SetupCheckSnapshot snapshot;
  final bool isRemote;
  final bool installing;
  final int selectedCount;
  final VoidCallback onRefresh;
  final VoidCallback? onInstall;
  final String? installScript;

  @override
  State<_SetupHeader> createState() => _SetupHeaderState();
}

class _SetupHeaderState extends State<_SetupHeader> {
  bool _copied = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final runtime = widget.snapshot.runtime;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.install_desktop_outlined,
                color: colors.accentBlue,
                size: 18,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  widget.isRemote
                      ? 'Remote machine setup'
                      : 'Local machine setup',
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Refresh',
                onPressed: widget.installing ? null : widget.onRefresh,
                icon: const Icon(Icons.refresh_rounded, size: 18),
                color: colors.textMuted,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              _Badge(label: runtime.osLabel),
              if (runtime.versionLabel.isNotEmpty)
                _Badge(label: runtime.versionLabel),
              _Badge(label: runtime.packageManager),
              _Badge(
                label:
                    widget.snapshot.allRequiredAvailable
                        ? 'required ready'
                        : 'required missing',
                color:
                    widget.snapshot.allRequiredAvailable
                        ? colors.accentGreen
                        : colors.accentOrange,
              ),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 34,
            child: ElevatedButton.icon(
              onPressed: widget.onInstall,
              icon:
                  widget.installing
                      ? SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          color: colors.textPrimary,
                          strokeWidth: 2,
                        ),
                      )
                      : const Icon(Icons.play_arrow_rounded, size: 17),
              label: Text(
                widget.installing
                    ? 'Installing...'
                    : 'Install selected (${widget.selectedCount})',
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: colors.accentBlue,
                foregroundColor: colors.textPrimary,
                textStyle: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Output log is read-only. Copy command if you want to inspect or run it manually.',
                  style: TextStyle(color: colors.textMuted, fontSize: 10),
                ),
              ),
              TextButton.icon(
                onPressed:
                    widget.installScript == null
                        ? null
                        : () async {
                          await Clipboard.setData(
                            ClipboardData(text: widget.installScript!),
                          );
                          if (!mounted) return;
                          setState(() => _copied = true);
                          await Future<void>.delayed(
                            const Duration(seconds: 2),
                          );
                          if (mounted) setState(() => _copied = false);
                        },
                icon: Icon(_copied ? Icons.check : Icons.copy, size: 14),
                label: Text(_copied ? 'Copied' : 'Copy command'),
                style: TextButton.styleFrom(
                  foregroundColor: colors.accentBlue,
                  textStyle: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
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

class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    required this.packages,
    required this.selectedIds,
    required this.onToggle,
  });

  final String title;
  final List<SetupPackageStatus> packages;
  final Set<String> selectedIds;
  final void Function(String id, bool selected) onToggle;

  @override
  Widget build(BuildContext context) {
    if (packages.isEmpty) return const SizedBox.shrink();
    final colors = context.appColors;
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              color: colors.textMuted,
              fontSize: 11,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          ...packages.map(
            (pkg) => _PackageTile(
              pkg: pkg,
              selected: selectedIds.contains(pkg.id),
              onChanged: (value) => onToggle(pkg.id, value),
            ),
          ),
        ],
      ),
    );
  }
}

class _PackageTile extends StatelessWidget {
  const _PackageTile({
    required this.pkg,
    required this.selected,
    required this.onChanged,
  });

  final SetupPackageStatus pkg;
  final bool selected;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final available = pkg.available;
    final canInstall = pkg.installAction != null;
    return Container(
      margin: const EdgeInsets.only(bottom: 7),
      decoration: BoxDecoration(
        color: colors.surfaceElevated,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color:
              available
                  ? colors.accentGreen.withAlpha(70)
                  : selected
                  ? colors.accentBlue.withAlpha(120)
                  : colors.border,
        ),
      ),
      child: CheckboxListTile(
        value: selected,
        onChanged:
            available || !canInstall
                ? null
                : (value) => onChanged(value ?? false),
        dense: true,
        controlAffinity: ListTileControlAffinity.leading,
        activeColor: colors.accentBlue,
        checkboxShape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(4),
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                pkg.name,
                style: TextStyle(
                  color: colors.textPrimary,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            if (pkg.required)
              const _Badge(label: 'required', color: Colors.redAccent),
            const SizedBox(width: 6),
            _Badge(
              label:
                  available
                      ? 'ready'
                      : canInstall
                      ? 'missing'
                      : 'manual',
              color:
                  available
                      ? colors.accentGreen
                      : canInstall
                      ? colors.accentOrange
                      : colors.textMuted,
            ),
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              pkg.description,
              style: TextStyle(color: colors.textMuted, fontSize: 10),
            ),
            if (pkg.version != null)
              Text(
                pkg.version!,
                style: TextStyle(color: colors.accentGreen, fontSize: 10),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              )
            else if (pkg.installAction != null)
              Text(
                pkg.installAction!.command,
                style: TextStyle(
                  color: colors.textMuted,
                  fontFamily: 'monospace',
                  fontSize: 9,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
          ],
        ),
      ),
    );
  }
}

class _InstallLog extends StatelessWidget {
  const _InstallLog({required this.lines, required this.controller});

  final List<String> lines;
  final ScrollController controller;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Container(
      height: 150,
      margin: const EdgeInsets.only(top: 4),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: colors.background,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.border),
      ),
      child: ListView.builder(
        controller: controller,
        itemCount: lines.length,
        itemBuilder: (_, index) {
          final line = lines[index];
          return Text(
            line,
            style: TextStyle(
              color:
                  line.startsWith('[exit 0]')
                      ? colors.accentGreen
                      : line.startsWith('[error]') || line.contains('[exit ')
                      ? Colors.red.shade300
                      : colors.textPrimary,
              fontFamily: 'monospace',
              fontSize: 10,
            ),
          );
        },
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.label, this.color});

  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final tint = color ?? colors.accentBlue;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: tint.withAlpha(24),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: tint.withAlpha(80)),
      ),
      child: Text(
        label,
        style: TextStyle(color: tint, fontSize: 9, fontWeight: FontWeight.w800),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.error, required this.onRetry});

  final String error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, color: Colors.red.shade300, size: 28),
            const SizedBox(height: 10),
            Text(
              error,
              textAlign: TextAlign.center,
              style: TextStyle(color: colors.textMuted, fontSize: 12),
            ),
            const SizedBox(height: 12),
            TextButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded, size: 15),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}
