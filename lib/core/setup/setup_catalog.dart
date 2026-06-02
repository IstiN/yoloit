import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:yoloit/core/skills/yoloit_global_skills_service.dart';

enum SetupTargetOs { macos, linux, windows, unknown }

enum SetupPackageCategory { system, agents, optional }

class SetupRuntimeInfo {
  const SetupRuntimeInfo({
    required this.os,
    required this.osLabel,
    required this.versionLabel,
    required this.packageManager,
    required this.homeDirectory,
  });

  final SetupTargetOs os;
  final String osLabel;
  final String versionLabel;
  final String packageManager;
  final String homeDirectory;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'os': os.name,
    'osLabel': osLabel,
    'versionLabel': versionLabel,
    'packageManager': packageManager,
    'homeDirectory': homeDirectory,
  };

  factory SetupRuntimeInfo.fromJson(Map<String, dynamic> json) {
    return SetupRuntimeInfo(
      os: SetupTargetOs.values.firstWhere(
        (value) => value.name == json['os'],
        orElse: () => SetupTargetOs.unknown,
      ),
      osLabel: json['osLabel'] as String? ?? 'Unknown OS',
      versionLabel: json['versionLabel'] as String? ?? '',
      packageManager: json['packageManager'] as String? ?? 'shell',
      homeDirectory: json['homeDirectory'] as String? ?? '',
    );
  }
}

class SetupInstallAction {
  const SetupInstallAction({
    required this.command,
    this.requiresInteraction = false,
  });

  final String command;
  final bool requiresInteraction;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'command': command,
    'requiresInteraction': requiresInteraction,
  };

  factory SetupInstallAction.fromJson(Map<String, dynamic> json) {
    return SetupInstallAction(
      command: json['command'] as String? ?? '',
      requiresInteraction: json['requiresInteraction'] == true,
    );
  }
}

class SetupPackageSpec {
  const SetupPackageSpec({
    required this.id,
    required this.name,
    required this.category,
    required this.description,
    required this.command,
    required this.versionArgs,
    required this.install,
    this.required = false,
  });

  final String id;
  final String name;
  final SetupPackageCategory category;
  final String description;
  final String command;
  final List<String> versionArgs;
  final bool required;
  final Map<SetupTargetOs, SetupInstallAction> install;

  SetupInstallAction? installAction(SetupTargetOs os) => install[os];
}

class SetupPackageStatus {
  const SetupPackageStatus({
    required this.id,
    required this.name,
    required this.category,
    required this.description,
    required this.command,
    required this.required,
    required this.available,
    this.version,
    this.installAction,
  });

  final String id;
  final String name;
  final SetupPackageCategory category;
  final String description;
  final String command;
  final bool required;
  final bool available;
  final String? version;
  final SetupInstallAction? installAction;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'name': name,
    'category': category.name,
    'description': description,
    'command': command,
    'required': required,
    'available': available,
    if (version != null) 'version': version,
    if (installAction != null) 'installAction': installAction!.toJson(),
  };

  factory SetupPackageStatus.fromJson(Map<String, dynamic> json) {
    return SetupPackageStatus(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      category: SetupPackageCategory.values.firstWhere(
        (value) => value.name == json['category'],
        orElse: () => SetupPackageCategory.optional,
      ),
      description: json['description'] as String? ?? '',
      command: json['command'] as String? ?? '',
      required: json['required'] == true,
      available: json['available'] == true,
      version: json['version'] as String?,
      installAction:
          json['installAction'] is Map
              ? SetupInstallAction.fromJson(
                Map<String, dynamic>.from(json['installAction'] as Map),
              )
              : null,
    );
  }
}

class SetupCheckSnapshot {
  const SetupCheckSnapshot({required this.runtime, required this.packages});

  final SetupRuntimeInfo runtime;
  final List<SetupPackageStatus> packages;

  bool get allRequiredAvailable =>
      packages.where((pkg) => pkg.required).every((pkg) => pkg.available);

  Map<String, dynamic> toJson() => <String, dynamic>{
    'runtime': runtime.toJson(),
    'packages': packages.map((pkg) => pkg.toJson()).toList(),
  };

  factory SetupCheckSnapshot.fromJson(Map<String, dynamic> json) {
    return SetupCheckSnapshot(
      runtime: SetupRuntimeInfo.fromJson(
        Map<String, dynamic>.from(json['runtime'] as Map? ?? const {}),
      ),
      packages:
          (json['packages'] as List? ?? const <Object?>[])
              .whereType<Map<Object?, Object?>>()
              .map(
                (entry) => SetupPackageStatus.fromJson(
                  Map<String, dynamic>.from(entry),
                ),
              )
              .toList(),
    );
  }
}

class SetupCatalog {
  const SetupCatalog._();

  static const String yoloitSkillsPackageId = 'yoloit-skills';

  static const List<SetupPackageSpec> packages = <SetupPackageSpec>[
    SetupPackageSpec(
      id: 'git',
      name: 'Git',
      category: SetupPackageCategory.system,
      description: 'Version control for file tree, diffs, history, and sync.',
      command: 'git',
      versionArgs: <String>['--version'],
      required: true,
      install: <SetupTargetOs, SetupInstallAction>{
        SetupTargetOs.macos: SetupInstallAction(command: 'brew install git'),
        SetupTargetOs.linux: SetupInstallAction(
          command: 'sudo apt-get update && sudo apt-get install -y git',
          requiresInteraction: true,
        ),
        SetupTargetOs.windows: SetupInstallAction(
          command: 'winget install --id Git.Git -e --source winget',
          requiresInteraction: true,
        ),
      },
    ),
    SetupPackageSpec(
      id: 'node',
      name: 'Node.js',
      category: SetupPackageCategory.system,
      description: 'Runtime for npm-based AI agents and developer tools.',
      command: 'node',
      versionArgs: <String>['--version'],
      install: <SetupTargetOs, SetupInstallAction>{
        SetupTargetOs.macos: SetupInstallAction(command: 'brew install node'),
        SetupTargetOs.linux: SetupInstallAction(
          command: 'sudo apt-get update && sudo apt-get install -y nodejs npm',
          requiresInteraction: true,
        ),
        SetupTargetOs.windows: SetupInstallAction(
          command: 'winget install --id OpenJS.NodeJS.LTS -e --source winget',
          requiresInteraction: true,
        ),
      },
    ),
    SetupPackageSpec(
      id: 'tmux',
      name: 'tmux',
      category: SetupPackageCategory.system,
      description: 'Persistent terminal sessions for long-running agents.',
      command: 'tmux',
      versionArgs: <String>['-V'],
      required: true,
      install: <SetupTargetOs, SetupInstallAction>{
        SetupTargetOs.macos: SetupInstallAction(command: 'brew install tmux'),
        SetupTargetOs.linux: SetupInstallAction(
          command: 'sudo apt-get update && sudo apt-get install -y tmux',
          requiresInteraction: true,
        ),
      },
    ),
    SetupPackageSpec(
      id: 'bash',
      name: 'bash',
      category: SetupPackageCategory.system,
      description: 'Shell used by board commands and remote terminal sessions.',
      command: 'bash',
      versionArgs: <String>['--version'],
      required: true,
      install: <SetupTargetOs, SetupInstallAction>{
        SetupTargetOs.macos: SetupInstallAction(command: 'brew install bash'),
        SetupTargetOs.linux: SetupInstallAction(
          command: 'sudo apt-get update && sudo apt-get install -y bash',
          requiresInteraction: true,
        ),
      },
    ),
    SetupPackageSpec(
      id: 'codex',
      name: 'Codex CLI',
      category: SetupPackageCategory.agents,
      description: 'OpenAI coding agent that runs in the terminal.',
      command: 'codex',
      versionArgs: <String>['--version'],
      install: <SetupTargetOs, SetupInstallAction>{
        SetupTargetOs.macos: SetupInstallAction(
          command: 'curl -fsSL https://chatgpt.com/codex/install.sh | sh',
        ),
        SetupTargetOs.linux: SetupInstallAction(
          command:
              'if command -v npm >/dev/null 2>&1; then npm install -g @openai/codex; else curl -fsSL https://chatgpt.com/codex/install.sh | sh; fi',
        ),
        SetupTargetOs.windows: SetupInstallAction(
          command:
              'powershell -ExecutionPolicy ByPass -c "irm https://chatgpt.com/codex/install.ps1 | iex"',
          requiresInteraction: true,
        ),
      },
    ),
    SetupPackageSpec(
      id: 'claude',
      name: 'Claude Code',
      category: SetupPackageCategory.agents,
      description: 'Anthropic agent CLI.',
      command: 'claude',
      versionArgs: <String>['--version'],
      install: <SetupTargetOs, SetupInstallAction>{
        SetupTargetOs.macos: SetupInstallAction(
          command: 'npm install -g @anthropic-ai/claude-code',
        ),
        SetupTargetOs.linux: SetupInstallAction(
          command: 'npm install -g @anthropic-ai/claude-code',
        ),
        SetupTargetOs.windows: SetupInstallAction(
          command: 'npm install -g @anthropic-ai/claude-code',
        ),
      },
    ),
    SetupPackageSpec(
      id: 'gemini',
      name: 'Gemini CLI',
      category: SetupPackageCategory.agents,
      description: 'Google agent CLI.',
      command: 'gemini',
      versionArgs: <String>['--version'],
      install: <SetupTargetOs, SetupInstallAction>{
        SetupTargetOs.macos: SetupInstallAction(
          command: 'npm install -g @google/gemini-cli',
        ),
        SetupTargetOs.linux: SetupInstallAction(
          command: 'npm install -g @google/gemini-cli',
        ),
        SetupTargetOs.windows: SetupInstallAction(
          command: 'npm install -g @google/gemini-cli',
        ),
      },
    ),
    SetupPackageSpec(
      id: 'kimi',
      name: 'Kimi Code CLI',
      category: SetupPackageCategory.agents,
      description: 'Moonshot AI terminal coding agent.',
      command: 'kimi',
      versionArgs: <String>['--version'],
      install: <SetupTargetOs, SetupInstallAction>{
        SetupTargetOs.macos: SetupInstallAction(
          command:
              'curl -fsSL https://code.kimi.com/kimi-code/install.sh | bash',
        ),
        SetupTargetOs.linux: SetupInstallAction(
          command:
              'curl -fsSL https://code.kimi.com/kimi-code/install.sh | bash',
        ),
        SetupTargetOs.windows: SetupInstallAction(
          command:
              'powershell -ExecutionPolicy ByPass -c "irm https://code.kimi.com/kimi-code/install.ps1 | iex"',
          requiresInteraction: true,
        ),
      },
    ),
    SetupPackageSpec(
      id: 'opencode',
      name: 'OpenCode',
      category: SetupPackageCategory.agents,
      description: 'Terminal AI coding agent.',
      command: 'opencode',
      versionArgs: <String>['--version'],
      install: <SetupTargetOs, SetupInstallAction>{
        SetupTargetOs.macos: SetupInstallAction(
          command: 'brew install anomalyco/tap/opencode',
        ),
        SetupTargetOs.linux: SetupInstallAction(
          command: 'curl -fsSL https://opencode.ai/install | bash',
        ),
        SetupTargetOs.windows: SetupInstallAction(
          command: 'npm install -g opencode-ai',
        ),
      },
    ),
    SetupPackageSpec(
      id: 'aider',
      name: 'Aider',
      category: SetupPackageCategory.agents,
      description: 'AI pair programming CLI.',
      command: 'aider',
      versionArgs: <String>['--version'],
      install: <SetupTargetOs, SetupInstallAction>{
        SetupTargetOs.macos: SetupInstallAction(
          command: 'python3 -m pip install --user aider-chat',
        ),
        SetupTargetOs.linux: SetupInstallAction(
          command: 'python3 -m pip install --user aider-chat',
        ),
        SetupTargetOs.windows: SetupInstallAction(
          command: 'py -m pip install --user aider-chat',
        ),
      },
    ),
    SetupPackageSpec(
      id: yoloitSkillsPackageId,
      name: 'YoLoIT Global Skills',
      category: SetupPackageCategory.agents,
      description:
          'Installs and updates YoLoIT skills globally for Codex, Claude Code, Cursor, Copilot, Gemini, and Windsurf.',
      command: '__yoloit_global_skills__',
      versionArgs: <String>[],
      install: <SetupTargetOs, SetupInstallAction>{
        SetupTargetOs.macos: SetupInstallAction(
          command: 'YoLoIT built-in task: install/update global skills',
        ),
        SetupTargetOs.linux: SetupInstallAction(
          command: 'YoLoIT built-in task: install/update global skills',
        ),
        SetupTargetOs.windows: SetupInstallAction(
          command: 'YoLoIT built-in task: install/update global skills',
        ),
      },
    ),
    SetupPackageSpec(
      id: 'docker',
      name: 'Docker',
      category: SetupPackageCategory.optional,
      description: 'Container runtime for local yoloitd and dev services.',
      command: 'docker',
      versionArgs: <String>['--version'],
      install: <SetupTargetOs, SetupInstallAction>{
        SetupTargetOs.macos: SetupInstallAction(
          command: 'brew install --cask docker',
        ),
        SetupTargetOs.linux: SetupInstallAction(
          command: 'sudo apt-get update && sudo apt-get install -y docker.io',
          requiresInteraction: true,
        ),
        SetupTargetOs.windows: SetupInstallAction(
          command:
              'winget install --id Docker.DockerDesktop -e --source winget',
          requiresInteraction: true,
        ),
      },
    ),
  ];

  static Future<SetupRuntimeInfo> detectRuntime() async {
    final os =
        Platform.isMacOS
            ? SetupTargetOs.macos
            : Platform.isLinux
            ? SetupTargetOs.linux
            : Platform.isWindows
            ? SetupTargetOs.windows
            : SetupTargetOs.unknown;
    return SetupRuntimeInfo(
      os: os,
      osLabel: await _osLabel(os),
      versionLabel: await _versionLabel(os),
      packageManager: await _packageManager(os),
      homeDirectory:
          Platform.environment['HOME'] ??
          Platform.environment['USERPROFILE'] ??
          '',
    );
  }

  static Future<SetupCheckSnapshot> check() async {
    final runtime = await detectRuntime();
    final statuses = await Future.wait(
      packages.map((spec) => _checkPackage(spec, runtime.os)),
    );
    return SetupCheckSnapshot(runtime: runtime, packages: statuses);
  }

  static String installScript(Iterable<String> packageIds, SetupTargetOs os) {
    final selected = packageIds.map((id) => id.trim()).toSet();
    final commands = <String>[];
    for (final spec in packages) {
      if (!selected.contains(spec.id)) continue;
      if (isSpecialInstallTask(spec.id)) continue;
      final action = spec.installAction(os);
      if (action == null || action.command.trim().isEmpty) continue;
      commands.add(_normalizeInstallCommand(action.command.trim(), os));
    }
    return installBatchScript(commands);
  }

  static bool isSpecialInstallTask(String packageId) =>
      packageId == yoloitSkillsPackageId;

  static String specialInstallLabel(String packageId) {
    if (packageId == yoloitSkillsPackageId) {
      return 'YoLoIT built-in task: install/update global skills';
    }
    return '';
  }

  static Stream<String> runSpecialInstallTask(String packageId) {
    if (packageId == yoloitSkillsPackageId) {
      return YoloitGlobalSkillsService.instance.installOrUpdate();
    }
    final controller = StreamController<String>();
    controller.add('[error] Unknown special install task: $packageId');
    unawaited(controller.close());
    return controller.stream;
  }

  static String installBatchScript(Iterable<String> commands) {
    final buffer = StringBuffer('set +e\n');
    var index = 0;
    for (final command in commands) {
      final trimmed = command.trim();
      if (trimmed.isEmpty) continue;
      index++;
      buffer.writeln('echo "==> [$index] ${_escapeDoubleQuoted(trimmed)}"');
      buffer.writeln('($trimmed)');
      buffer.writeln(
        'code=\$?; if [ \$code -eq 0 ]; then echo "==> [$index] ok"; else echo "==> [$index] failed: \$code"; fi',
      );
    }
    return buffer.toString().trim();
  }

  static String _normalizeInstallCommand(String command, SetupTargetOs os) {
    if (os == SetupTargetOs.linux && _shouldDropSudo()) {
      return command.replaceAllMapped(
        RegExp(r'(^|&&\s*)sudo\s+'),
        (match) => match.group(1) ?? '',
      );
    }
    return command;
  }

  static bool _shouldDropSudo() {
    final user = Platform.environment['USER'] ?? '';
    if (user == 'root') return true;
    return !File('/usr/bin/sudo').existsSync() &&
        !File('/bin/sudo').existsSync();
  }

  static SetupInstallAction? _normalizedAction(
    SetupInstallAction? action,
    SetupTargetOs os,
  ) {
    if (action == null) return null;
    return SetupInstallAction(
      command: _normalizeInstallCommand(action.command, os),
      requiresInteraction: action.requiresInteraction,
    );
  }

  static Future<SetupPackageStatus> _checkPackage(
    SetupPackageSpec spec,
    SetupTargetOs os,
  ) async {
    if (spec.id == yoloitSkillsPackageId) {
      final status = await YoloitGlobalSkillsService.instance.check();
      return SetupPackageStatus(
        id: spec.id,
        name: spec.name,
        category: spec.category,
        description: spec.description,
        command: spec.command,
        required: spec.required,
        available: status.installed,
        version: status.summary,
        installAction: _normalizedAction(spec.installAction(os), os),
      );
    }
    final path = await _findPath(spec.command);
    if (path == null) {
      return SetupPackageStatus(
        id: spec.id,
        name: spec.name,
        category: spec.category,
        description: spec.description,
        command: spec.command,
        required: spec.required,
        available: false,
        installAction: _normalizedAction(spec.installAction(os), os),
      );
    }
    final version = await _version(path, spec.versionArgs);
    return SetupPackageStatus(
      id: spec.id,
      name: spec.name,
      category: spec.category,
      description: spec.description,
      command: spec.command,
      required: spec.required,
      available: true,
      version: version,
      installAction: _normalizedAction(spec.installAction(os), os),
    );
  }

  static Future<String?> _findPath(String command) async {
    try {
      final shell = Platform.isWindows ? 'where' : '/bin/sh';
      final args =
          Platform.isWindows
              ? <String>[command]
              : <String>['-lc', 'command -v ${_shellQuote(command)}'];
      final result = await Process.run(
        shell,
        args,
        environment: _extendedEnv(),
        runInShell: Platform.isWindows,
      ).timeout(const Duration(seconds: 5));
      if (result.exitCode != 0) return null;
      final out = (result.stdout as String).trim();
      return out.isEmpty ? null : out.split('\n').first.trim();
    } catch (_) {
      return null;
    }
  }

  static Future<String?> _version(String executable, List<String> args) async {
    try {
      final result = await Process.run(
        executable,
        args,
        environment: _extendedEnv(),
        runInShell: Platform.isWindows,
      ).timeout(const Duration(seconds: 5));
      final raw =
          (result.stdout as String).trim().isNotEmpty
              ? (result.stdout as String).trim()
              : (result.stderr as String).trim();
      if (raw.isEmpty) return null;
      return raw.split('\n').first.trim();
    } catch (_) {
      return null;
    }
  }

  static Future<String> _osLabel(SetupTargetOs os) async {
    if (os == SetupTargetOs.macos) return 'macOS';
    if (os == SetupTargetOs.windows) return 'Windows';
    if (os == SetupTargetOs.linux) {
      final release = await _linuxOsRelease();
      return release['PRETTY_NAME'] ?? release['NAME'] ?? 'Linux';
    }
    return Platform.operatingSystem;
  }

  static Future<String> _versionLabel(SetupTargetOs os) async {
    if (os == SetupTargetOs.linux) {
      final release = await _linuxOsRelease();
      return release['VERSION'] ?? release['VERSION_ID'] ?? '';
    }
    try {
      final result =
          os == SetupTargetOs.macos
              ? await Process.run('sw_vers', <String>['-productVersion'])
              : os == SetupTargetOs.windows
              ? await Process.run('cmd', <String>['/c', 'ver'])
              : null;
      return (result?.stdout as String? ?? '').trim();
    } catch (_) {
      return '';
    }
  }

  static Future<String> _packageManager(SetupTargetOs os) async {
    if (os == SetupTargetOs.macos) {
      return await _findPath('brew') == null ? 'shell' : 'brew';
    }
    if (os == SetupTargetOs.windows) {
      return await _findPath('winget') == null ? 'shell' : 'winget';
    }
    if (os == SetupTargetOs.linux) {
      if (await _findPath('apt-get') != null) return 'apt';
      if (await _findPath('dnf') != null) return 'dnf';
      if (await _findPath('pacman') != null) return 'pacman';
    }
    return 'shell';
  }

  static Future<Map<String, String>> _linuxOsRelease() async {
    try {
      final file = File('/etc/os-release');
      if (!await file.exists()) return const <String, String>{};
      final lines = await file.readAsLines();
      return <String, String>{
        for (final line in lines)
          if (line.contains('='))
            line.split('=').first: line
                .substring(line.indexOf('=') + 1)
                .replaceAll('"', ''),
      };
    } catch (_) {
      return const <String, String>{};
    }
  }

  static Map<String, String> _extendedEnv() {
    final env = Map<String, String>.from(Platform.environment);
    final current = env['PATH'] ?? '';
    final home = env['HOME'] ?? env['USERPROFILE'] ?? '';
    final extras = <String>[
      '/opt/homebrew/bin',
      '/usr/local/bin',
      '/usr/bin',
      '/bin',
      '/usr/sbin',
      '/sbin',
      if (home.isNotEmpty) '$home/.local/bin',
      if (home.isNotEmpty) '$home/.cargo/bin',
      if (home.isNotEmpty) '$home/.npm-global/bin',
      if (home.isNotEmpty) '$home/.nvm/versions/node/current/bin',
    ];
    env['PATH'] = <String>{
      ...extras.where((entry) => entry.isNotEmpty),
      ...current.split(Platform.isWindows ? ';' : ':'),
    }.where((entry) => entry.isNotEmpty).join(Platform.isWindows ? ';' : ':');
    return env;
  }

  static String _shellQuote(String value) =>
      "'${value.replaceAll("'", "'\\''")}'";

  static String _escapeDoubleQuoted(String value) => value
      .replaceAll(r'\', r'\\')
      .replaceAll('"', r'\"')
      .replaceAll(r'$', r'\$');
}

Stream<String> runSetupInstallScript(
  String script, {
  String? workingDirectory,
}) {
  final controller = StreamController<String>();
  () async {
    try {
      final shell =
          Platform.isWindows
              ? 'powershell'
              : Platform.environment['SHELL'] ?? '/bin/sh';
      final args =
          Platform.isWindows
              ? <String>[
                '-NoProfile',
                '-ExecutionPolicy',
                'Bypass',
                '-Command',
                script,
              ]
              : <String>['-lc', script];
      final process = await Process.start(
        shell,
        args,
        workingDirectory: workingDirectory,
        environment: SetupCatalog._extendedEnv(),
      );
      process.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(controller.add);
      process.stderr
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(controller.add);
      final exitCode = await process.exitCode;
      controller.add('[exit $exitCode]');
    } catch (error) {
      controller.add('[error] $error');
    } finally {
      await controller.close();
    }
  }();
  return controller.stream;
}
