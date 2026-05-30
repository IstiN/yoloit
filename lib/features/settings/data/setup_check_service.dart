import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:yoloit/core/platform/platform_launcher.dart';

// ── InstallAction ─────────────────────────────────────────────────────────────

/// Describes how to install a dependency.
class InstallAction {
  const InstallAction({
    required this.executable,
    required this.args,
    this.requiresInteractiveTerminal = false,
    this.interactiveScript,
  });

  final String executable;
  final List<String> args;

  /// If true, this command is interactive (needs sudo/TTY) — opens Terminal.
  final bool requiresInteractiveTerminal;

  /// Shell script to run inside Terminal when [requiresInteractiveTerminal] is true.
  final String? interactiveScript;

  String get displayCommand =>
      interactiveScript ?? '$executable ${args.join(' ')}'.trim();
}

// ── DependencyStatus ──────────────────────────────────────────────────────────

/// Result of a single dependency/agent check.
class DependencyStatus {
  const DependencyStatus({
    required this.id,
    required this.name,
    required this.description,
    required this.installHint,
    required this.isAvailable,
    this.version,
    this.installUrl,
    this.installAction,
    this.isRequired = true,
  });

  final String id;
  final String name;
  final String description;
  final String installHint;
  final bool isAvailable;
  final String? version;
  final String? installUrl;

  /// Structured install action — null means copy-to-clipboard only.
  final InstallAction? installAction;
  final bool isRequired;
}

// ── SetupCheckResult ──────────────────────────────────────────────────────────

/// Result of checking all dependencies and agents.
class SetupCheckResult {
  const SetupCheckResult({required this.deps, required this.agents});

  final List<DependencyStatus> deps;
  final List<DependencyStatus> agents;

  bool get allRequiredDepsOk =>
      deps.where((d) => d.isRequired).every((d) => d.isAvailable);

  bool get anyAgentAvailable => agents.any((a) => a.isAvailable);
}

// ── SetupCheckService ─────────────────────────────────────────────────────────

/// Checks which system dependencies and AI agents are available.
class SetupCheckService {
  const SetupCheckService._();

  // ── Platform helpers ─────────────────────────────────────────────────────

  static bool get _isWindows => Platform.isWindows;
  static bool get _isMacOS => Platform.isMacOS;

  // ── Extended PATH ────────────────────────────────────────────────────────

  static String _buildExtendedPathMacOS() {
    final current = Platform.environment['PATH'] ?? '';
    final home = Platform.environment['HOME'] ?? '';

    final candidates = <String>[
      '/opt/homebrew/bin',
      '/opt/homebrew/sbin',
      '/usr/local/bin',
      '/usr/local/sbin',
      '/usr/bin',
      '/bin',
      '/usr/sbin',
      '/sbin',
    ];

    if (home.isNotEmpty) {
      candidates.addAll([
        '$home/.nvm/versions/node/current/bin',
        '$home/.kimi-code/bin',
        '$home/.volta/bin',
        '$home/.pyenv/shims',
        '$home/.pyenv/bin',
        '$home/.cargo/bin',
        '$home/.local/bin',
        '$home/bin',
      ]);

      // Probe NVM directory for installed versions (highest first)
      final nvmDir = '$home/.nvm/versions/node';
      try {
        final dir = Directory(nvmDir);
        if (dir.existsSync()) {
          final versions =
              dir.listSync().whereType<Directory>().map((d) => d.path).toList()
                ..sort((a, b) => b.compareTo(a));
          for (final v in versions.take(3)) {
            candidates.add('$v/bin');
          }
        }
      } catch (_) {}
    }

    final existing = current.split(':').where((p) => p.isNotEmpty).toSet();
    final merged = <String>[
      ...candidates.where((c) => !existing.contains(c)),
      ...current.split(':').where((p) => p.isNotEmpty),
    ];
    return merged.join(':');
  }

  static String _buildExtendedPathWindows() {
    final current = Platform.environment['PATH'] ?? '';
    final appData = Platform.environment['APPDATA'] ?? '';
    final localAppData = Platform.environment['LOCALAPPDATA'] ?? '';
    final programFiles =
        Platform.environment['ProgramFiles'] ?? r'C:\Program Files';
    final programFilesX86 =
        Platform.environment['ProgramFiles(x86)'] ?? r'C:\Program Files (x86)';
    final userProfile = Platform.environment['USERPROFILE'] ?? '';

    final candidates = <String>[
      r'C:\Windows\System32',
      r'C:\Windows',
      r'C:\Windows\System32\Wbem',
      '$programFiles\\Git\\bin',
      '$programFiles\\Git\\cmd',
      '$programFiles\\Git\\usr\\bin',
      '$programFiles\\nodejs',
      '$programFilesX86\\nodejs',
      if (appData.isNotEmpty) '$appData\\npm',
      if (localAppData.isNotEmpty) '$localAppData\\Microsoft\\WinGet\\Links',
      if (userProfile.isNotEmpty)
        '$userProfile\\AppData\\Local\\Microsoft\\WinGet\\Links',
      if (userProfile.isNotEmpty) '$userProfile\\.cargo\\bin',
      if (userProfile.isNotEmpty)
        '$userProfile\\AppData\\Local\\Programs\\Python\\Python3\\Scripts',
      // Cursor IDE — installs to LocalAppData/Programs/cursor/resources/app/bin
      if (localAppData.isNotEmpty)
        '$localAppData\\Programs\\cursor\\resources\\app\\bin',
      if (localAppData.isNotEmpty) '$localAppData\\Programs\\Cursor',
      // nvm / volta / fnm Node version managers
      if (appData.isNotEmpty) '$appData\\nvm',
      if (localAppData.isNotEmpty) '$localAppData\\Volta\\bin',
      if (localAppData.isNotEmpty) '$localAppData\\fnm',
    ];

    final existing = current.split(';').where((p) => p.isNotEmpty).toSet();
    final merged = <String>[
      ...candidates.where((c) => !existing.contains(c)),
      ...current.split(';').where((p) => p.isNotEmpty),
    ];
    return merged.join(';');
  }

  static String _buildExtendedPathLinux() {
    final current = Platform.environment['PATH'] ?? '';
    final home = Platform.environment['HOME'] ?? '';

    final candidates = <String>[
      '/usr/local/bin',
      '/usr/bin',
      '/bin',
      '/usr/sbin',
      '/sbin',
      if (home.isNotEmpty) '$home/.local/bin',
      if (home.isNotEmpty) '$home/.cargo/bin',
      if (home.isNotEmpty) '$home/.kimi-code/bin',
      if (home.isNotEmpty) '$home/.nvm/versions/node/current/bin',
      if (home.isNotEmpty) '$home/.volta/bin',
    ];

    final existing = current.split(':').where((p) => p.isNotEmpty).toSet();
    final merged = <String>[
      ...candidates.where((c) => !existing.contains(c)),
      ...current.split(':').where((p) => p.isNotEmpty),
    ];
    return merged.join(':');
  }

  static String? _extendedPath;
  static String get _path {
    if (_extendedPath != null) return _extendedPath!;
    if (_isWindows) return _extendedPath = _buildExtendedPathWindows();
    if (_isMacOS) return _extendedPath = _buildExtendedPathMacOS();
    return _extendedPath = _buildExtendedPathLinux();
  }

  @visibleForTesting
  static String debugExtendedPathForTesting() {
    _extendedPath = null;
    return _path;
  }

  static Map<String, String> get _env {
    final env = Map<String, String>.from(Platform.environment);
    env['PATH'] = _path;
    return env;
  }

  // ── Check ────────────────────────────────────────────────────────────────

  static Future<SetupCheckResult> check() async {
    _extendedPath = null; // reset so newly installed tools are detected
    return _checkAll();
  }

  static Future<SetupCheckResult> _checkAll() {
    return _isWindows ? _checkAllWindows() : _checkAllUnix();
  }

  // ── macOS / Linux dependency lists ───────────────────────────────────────

  static Future<SetupCheckResult> _checkAllUnix() async {
    final depFutures = _isMacOS ? _macOSDeps() : _linuxDeps();

    final agentFutures = _commonAgents(winget: false);

    final deps = await Future.wait(depFutures);
    final agents = await Future.wait(agentFutures);
    return SetupCheckResult(deps: deps, agents: agents);
  }

  static List<Future<DependencyStatus>> _macOSDeps() => [
    _checkTool(
      id: 'brew',
      name: 'Homebrew',
      description:
          'macOS package manager — needed to install other dependencies',
      command: 'brew',
      versionArgs: ['--version'],
      installHint:
          r'/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"',
      installUrl: 'https://brew.sh',
      isRequired: false,
      installAction: const InstallAction(
        executable: '/bin/bash',
        args: [],
        requiresInteractiveTerminal: true,
        interactiveScript:
            r'/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"',
      ),
    ),
    _checkTool(
      id: 'git',
      name: 'git',
      description: 'Version control — required for file tree, diff, branches',
      command: 'git',
      versionArgs: ['--version'],
      installHint: 'brew install git',
      installUrl: 'https://git-scm.com/downloads',
      isRequired: true,
      installAction: const InstallAction(
        executable: 'brew',
        args: ['install', 'git'],
      ),
    ),
    _checkTool(
      id: 'node',
      name: 'Node.js',
      description: 'Required for npm-based AI agents (Copilot, Claude, Gemini)',
      command: 'node',
      versionArgs: ['--version'],
      installHint: 'brew install node',
      installUrl: 'https://nodejs.org',
      isRequired: false,
      installAction: const InstallAction(
        executable: 'brew',
        args: ['install', 'node'],
      ),
    ),
    _checkTool(
      id: 'tmux',
      name: 'tmux',
      description:
          'Terminal multiplexer — required for persistent agent sessions',
      command: 'tmux',
      versionArgs: ['-V'],
      installHint: 'brew install tmux',
      installUrl: 'https://github.com/tmux/tmux',
      isRequired: true,
      installAction: const InstallAction(
        executable: 'brew',
        args: ['install', 'tmux'],
      ),
    ),
    _checkTool(
      id: 'bash',
      name: 'bash',
      description: 'Shell used for running commands in terminal sessions',
      command: 'bash',
      versionArgs: ['--version'],
      installHint: 'brew install bash',
      isRequired: true,
      installAction: const InstallAction(
        executable: 'brew',
        args: ['install', 'bash'],
      ),
    ),
  ];

  static List<Future<DependencyStatus>> _linuxDeps() => [
    _checkTool(
      id: 'git',
      name: 'git',
      description: 'Version control — required for file tree, diff, branches',
      command: 'git',
      versionArgs: ['--version'],
      installHint: 'sudo apt install git',
      installUrl: 'https://git-scm.com/downloads',
      isRequired: true,
      installAction: const InstallAction(
        executable: 'bash',
        args: ['-c', 'sudo apt-get install -y git'],
      ),
    ),
    _checkTool(
      id: 'node',
      name: 'Node.js',
      description: 'Required for npm-based AI agents (Copilot, Claude, Gemini)',
      command: 'node',
      versionArgs: ['--version'],
      installHint: 'sudo apt install nodejs npm',
      installUrl: 'https://nodejs.org',
      isRequired: false,
      installAction: const InstallAction(
        executable: 'bash',
        args: ['-c', 'sudo apt-get install -y nodejs npm'],
      ),
    ),
    _checkTool(
      id: 'tmux',
      name: 'tmux',
      description:
          'Terminal multiplexer — required for persistent agent sessions',
      command: 'tmux',
      versionArgs: ['-V'],
      installHint: 'sudo apt install tmux',
      installUrl: 'https://github.com/tmux/tmux',
      isRequired: true,
      installAction: const InstallAction(
        executable: 'bash',
        args: ['-c', 'sudo apt-get install -y tmux'],
      ),
    ),
    _checkTool(
      id: 'bash',
      name: 'bash',
      description: 'Shell used for running commands in terminal sessions',
      command: 'bash',
      versionArgs: ['--version'],
      installHint: 'sudo apt install bash',
      isRequired: true,
    ),
  ];

  // ── Windows dependency list ──────────────────────────────────────────────

  static Future<SetupCheckResult> _checkAllWindows() async {
    final depFutures = [
      _checkTool(
        id: 'winget',
        name: 'WinGet',
        description: 'Windows package manager — used to install dependencies',
        command: 'winget',
        versionArgs: ['--version'],
        installHint: 'Install "App Installer" from the Microsoft Store',
        installUrl: 'https://aka.ms/getwinget',
        isRequired: false,
        installAction: const InstallAction(
          executable: 'start',
          args: ['ms-windows-store://pdp/?productid=9NBLGGH4NNS1'],
          requiresInteractiveTerminal: true,
          interactiveScript: 'ms-windows-store://pdp/?productid=9NBLGGH4NNS1',
        ),
      ),
      _checkTool(
        id: 'git',
        name: 'git',
        description: 'Version control — required for file tree, diff, branches',
        command: 'git',
        versionArgs: ['--version'],
        installHint: 'winget install Git.Git',
        installUrl: 'https://git-scm.com/downloads',
        isRequired: true,
        installAction: const InstallAction(
          executable: 'winget',
          args: ['install', '--id', 'Git.Git', '-e', '--source', 'winget'],
        ),
      ),
      _checkTool(
        id: 'node',
        name: 'Node.js',
        description:
            'Required for npm-based AI agents (Copilot, Claude, Gemini)',
        command: 'node',
        versionArgs: ['--version'],
        installHint: 'winget install OpenJS.NodeJS.LTS',
        installUrl: 'https://nodejs.org',
        isRequired: false,
        installAction: const InstallAction(
          executable: 'winget',
          args: [
            'install',
            '--id',
            'OpenJS.NodeJS.LTS',
            '-e',
            '--source',
            'winget',
          ],
        ),
      ),
      _checkTool(
        id: 'powershell',
        name: 'PowerShell',
        description: 'Shell used for running commands in terminal sessions',
        command: 'powershell',
        versionArgs: ['-Command', r'$PSVersionTable.PSVersion.ToString()'],
        installHint: 'winget install Microsoft.PowerShell',
        isRequired: true,
      ),
      _checkTool(
        id: 'wt',
        name: 'Windows Terminal',
        description: 'Modern terminal — recommended for agent sessions',
        command: 'wt',
        versionArgs: ['--version'],
        installHint: 'winget install Microsoft.WindowsTerminal',
        installUrl: 'https://aka.ms/terminal',
        isRequired: false,
        installAction: const InstallAction(
          executable: 'winget',
          args: [
            'install',
            '--id',
            'Microsoft.WindowsTerminal',
            '-e',
            '--source',
            'winget',
          ],
        ),
      ),
    ];

    final agentFutures = _commonAgents(winget: true);

    final deps = await Future.wait(depFutures);
    final agents = await Future.wait(agentFutures);
    return SetupCheckResult(deps: deps, agents: agents);
  }

  // ── Common agent checks (macOS + Linux = npm, Windows adds winget) ───────

  static List<Future<DependencyStatus>> _commonAgents({
    required bool winget,
  }) => [
    _checkTool(
      id: 'copilot',
      name: 'GitHub Copilot',
      description: 'AI coding agent by GitHub — autonomous agentic CLI',
      command: 'copilot',
      versionArgs: ['--version'],
      installHint:
          winget
              ? 'winget install GitHub.Copilot'
              : 'npm install -g @github/copilot',
      installUrl: 'https://github.com/github/copilot-cli',
      isRequired: false,
      installAction:
          winget
              ? const InstallAction(
                executable: 'winget',
                args: [
                  'install',
                  '--id',
                  'GitHub.Copilot',
                  '-e',
                  '--source',
                  'winget',
                ],
              )
              : const InstallAction(
                executable: 'npm',
                args: ['install', '-g', '@github/copilot'],
              ),
    ),
    _checkTool(
      id: 'claude',
      name: 'Claude Code',
      description: 'AI coding agent by Anthropic',
      command: 'claude',
      versionArgs: ['--version'],
      installHint: 'npm install -g @anthropic-ai/claude-code',
      installUrl: 'https://claude.ai/code',
      isRequired: false,
      installAction: const InstallAction(
        executable: 'npm',
        args: ['install', '-g', '@anthropic-ai/claude-code'],
      ),
    ),
    _checkTool(
      id: 'gemini',
      name: 'Gemini CLI',
      description: 'AI coding agent by Google',
      command: 'gemini',
      versionArgs: ['--version'],
      installHint: 'npm install -g @google/gemini-cli',
      installUrl: 'https://gemini.google.com/cli',
      isRequired: false,
      installAction: const InstallAction(
        executable: 'npm',
        args: ['install', '-g', '@google/gemini-cli'],
      ),
    ),
    _checkTool(
      id: 'cursor',
      name: 'Cursor Agent',
      description: 'AI-first code editor with agent mode',
      command: 'cursor',
      versionArgs: ['--version'],
      installHint:
          winget
              ? 'winget install Anysphere.Cursor'
              : 'Download from cursor.com',
      installUrl: 'https://cursor.com',
      isRequired: false,
      installAction:
          winget
              ? const InstallAction(
                executable: 'winget',
                args: [
                  'install',
                  '--id',
                  'Anysphere.Cursor',
                  '-e',
                  '--source',
                  'winget',
                ],
              )
              : null,
    ),
    _checkTool(
      id: 'aider',
      name: 'Aider',
      description: 'AI pair programming in your terminal',
      command: 'aider',
      versionArgs: ['--version'],
      installHint: 'pip install aider-chat',
      installUrl: 'https://aider.chat',
      isRequired: false,
      installAction: const InstallAction(
        executable: 'pip',
        args: ['install', 'aider-chat'],
      ),
    ),
    _checkTool(
      id: 'opencode',
      name: 'OpenCode',
      description: 'AI coding agent for your terminal',
      command: 'opencode',
      versionArgs: ['--version'],
      installHint:
          winget
              ? 'npm i -g opencode-ai'
              : _isMacOS
              ? 'brew install anomalyco/tap/opencode'
              : 'curl -fsSL https://opencode.ai/install | bash',
      installUrl: 'https://opencode.ai',
      isRequired: false,
      installAction:
          winget
              ? const InstallAction(
                executable: 'npm',
                args: ['i', '-g', 'opencode-ai'],
              )
              : _isMacOS
              ? const InstallAction(
                executable: 'brew',
                args: ['install', 'anomalyco/tap/opencode'],
              )
              : const InstallAction(
                executable: 'bash',
                args: ['-c', 'curl -fsSL https://opencode.ai/install | bash'],
                requiresInteractiveTerminal: true,
              ),
    ),
  ];

  // ── Install (streaming) ──────────────────────────────────────────────────

  /// Runs the install action and streams output lines.
  static Stream<String> install(InstallAction action) {
    final controller = StreamController<String>();

    () async {
      try {
        if (action.requiresInteractiveTerminal) {
          await _openInTerminal(action.displayCommand);
          controller.add('ℹ️  Opened Terminal to run the installer.');
          controller.add(
            '   Please follow the instructions there, then click Re-check.',
          );
          await controller.close();
          return;
        }

        final resolvedExec = await _findExecutable(action.executable);

        final process = await Process.start(
          resolvedExec,
          action.args,
          environment: _env,
          runInShell: _isWindows, // winget needs shell on Windows
        );

        final outSub = process.stdout
            .transform(utf8.decoder)
            .transform(const LineSplitter())
            .listen(controller.add);

        final errSub = process.stderr
            .transform(utf8.decoder)
            .transform(const LineSplitter())
            .listen(controller.add);

        final exitCode = await process.exitCode;
        await Future.wait([outSub.asFuture<void>(), errSub.asFuture<void>()]);
        await outSub.cancel();
        await errSub.cancel();

        if (exitCode == 0) {
          controller.add('\n✅ Installation complete!');
        } else {
          controller.add('\n❌ Failed (exit code $exitCode)');
        }
      } catch (e) {
        controller.add('❌ Error: $e');
      } finally {
        await controller.close();
      }
    }();

    return controller.stream;
  }

  static Future<void> _openInTerminal(String command) async {
    await PlatformLauncher.instance.openTerminal(command);
  }

  // ── Internal check helper ────────────────────────────────────────────────

  /// Find the absolute path of [cmd].
  ///
  /// On Windows we first try PowerShell's `Get-Command` which reads PATH from
  /// the registry (HKLM + HKCU), so it sees tools installed after the app
  /// launched. Falls back to `where.exe` with our extended PATH as a backup.
  /// Public helper — returns true if [cmd] is on the PATH (uses the same
  /// extended-PATH lookup as the Setup Guide so results are consistent).
  static Future<bool> isCommandAvailable(String cmd) async {
    return (await _findPath(cmd)) != null;
  }

  static Future<String?> _findPath(String cmd) async {
    if (_isWindows) {
      return _findPathWindows(cmd);
    }
    try {
      final r = await Process.run('/bin/bash', [
        '-c',
        'which "$cmd" 2>/dev/null',
      ], environment: _env).timeout(const Duration(seconds: 5));
      final out = (r.stdout as String).trim().split('\n').first.trim();
      return (r.exitCode == 0 && out.isNotEmpty) ? out : null;
    } catch (_) {
      return null;
    }
  }

  /// Windows-specific path resolution.
  /// Uses PowerShell `Get-Command` (reads registry PATH) then falls back to
  /// `where.exe` with our manually extended PATH.
  static Future<String?> _findPathWindows(String cmd) async {
    // 1) PowerShell Get-Command — always reads the current registry PATH
    try {
      final r = await Process.run('powershell', [
        '-NoProfile',
        '-NonInteractive',
        '-Command',
        'try { (Get-Command "$cmd" -ErrorAction Stop).Source } catch { exit 1 }',
      ], runInShell: false).timeout(const Duration(seconds: 8));
      final out = (r.stdout as String).trim().split('\n').first.trim();
      if (r.exitCode == 0 && out.isNotEmpty) return out;
    } catch (_) {}

    // 2) where.exe with our extended PATH as fallback
    try {
      final r = await Process.run(
        'where',
        [cmd],
        environment: _env,
        runInShell: true,
      ).timeout(const Duration(seconds: 5));
      final out = (r.stdout as String).trim().split('\n').first.trim();
      if (r.exitCode == 0 && out.isNotEmpty) return out;
    } catch (_) {}

    return null;
  }

  static Future<String> _findExecutable(String exe) async {
    return await _findPath(exe) ?? exe;
  }

  static Future<DependencyStatus> _checkTool({
    required String id,
    required String name,
    required String description,
    required String command,
    required List<String> versionArgs,
    required String installHint,
    String? fallbackCommand,
    List<String>? fallbackVersionArgs,
    String? installUrl,
    InstallAction? installAction,
    bool isRequired = false,
  }) async {
    final env = _env;

    Future<DependencyStatus?> tryCommand(
      String cmd,
      List<String> verArgs,
    ) async {
      try {
        final resolvedPath = await _findPath(cmd);
        if (resolvedPath == null) return null;

        final versionResult = await Process.run(
          resolvedPath,
          verArgs,
          environment: env,
          runInShell: _isWindows,
        ).timeout(const Duration(seconds: 5));

        final versionOutput =
            (versionResult.stdout as String).trim().isNotEmpty
                ? (versionResult.stdout as String).trim().split('\n').first
                : (versionResult.stderr as String).trim().split('\n').first;

        return DependencyStatus(
          id: id,
          name: name,
          description: description,
          installHint: installHint,
          installUrl: installUrl,
          installAction: installAction,
          isAvailable: true,
          version: _cleanVersion(versionOutput),
          isRequired: isRequired,
        );
      } catch (_) {
        return null;
      }
    }

    final primary = await tryCommand(command, versionArgs);
    if (primary != null) return primary;

    if (fallbackCommand != null) {
      final fallback = await tryCommand(
        fallbackCommand,
        fallbackVersionArgs ?? versionArgs,
      );
      if (fallback != null) return fallback;
    }

    return DependencyStatus(
      id: id,
      name: name,
      description: description,
      installHint: installHint,
      installUrl: installUrl,
      installAction: installAction,
      isAvailable: false,
      isRequired: isRequired,
    );
  }

  static String _cleanVersion(String raw) {
    final match = RegExp(r'[\d]+\.[\d]+[\.\d]*').firstMatch(raw);
    return match != null
        ? match.group(0)!
        : raw.length > 40
        ? raw.substring(0, 40)
        : raw;
  }
}

/// Describes how to install a dependency.
