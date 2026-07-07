import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yoloit/features/runs/models/run_config.dart';
import 'package:yoloit/features/runs/models/run_session.dart';

void main() {
  // ── RunConfig ──────────────────────────────────────────────────────────────
  group('RunConfig', () {
    const base = RunConfig(
      id: 'test-id',
      name: 'My Run',
      command: 'flutter run',
      workingDir: '/workspace',
      isFlutterRun: true,
    );

    test('default env is empty', () {
      const c = RunConfig(id: 'x', name: 'x', command: 'x');
      expect(c.env, isEmpty);
    });

    test('default isFlutterRun is false', () {
      const c = RunConfig(id: 'x', name: 'x', command: 'x');
      expect(c.isFlutterRun, false);
    });

    group('copyWith', () {
      test('copies name', () {
        expect(base.copyWith(name: 'New').name, 'New');
      });

      test('copies command', () {
        expect(base.copyWith(command: 'dart run').command, 'dart run');
      });

      test('clearWorkingDir sets workingDir to null', () {
        final c = base.copyWith(clearWorkingDir: true);
        expect(c.workingDir, isNull);
      });

      test('clearColor sets color to null', () {
        const colored = RunConfig(id: 'x', name: 'x', command: 'x', color: Colors.red);
        expect(colored.copyWith(clearColor: true).color, isNull);
      });

      test('preserves unchanged fields', () {
        final c = base.copyWith(name: 'Other');
        expect(c.id, 'test-id');
        expect(c.command, 'flutter run');
        expect(c.workingDir, '/workspace');
        expect(c.isFlutterRun, true);
      });
    });

    group('JSON serialization', () {
      test('toJson / fromJson round-trip', () {
        const cfg = RunConfig(
          id: 'rt-id',
          name: 'Round Trip',
          command: 'echo hello',
          workingDir: '/tmp',
          env: {'KEY': 'VALUE'},
          isFlutterRun: false,
        );
        final json = cfg.toJson();
        final restored = RunConfig.fromJson(json);
        expect(restored.id, cfg.id);
        expect(restored.name, cfg.name);
        expect(restored.command, cfg.command);
        expect(restored.workingDir, cfg.workingDir);
        expect(restored.env, cfg.env);
        expect(restored.isFlutterRun, cfg.isFlutterRun);
      });

      test('fromJson with missing optional fields uses defaults', () {
        final json = {'id': 'x', 'name': 'x', 'command': 'x'};
        final cfg = RunConfig.fromJson(json);
        expect(cfg.workingDir, isNull);
        expect(cfg.env, isEmpty);
        expect(cfg.color, isNull);
        expect(cfg.isFlutterRun, false);
      });

      test('color round-trips via toARGB32', () {
        const cfg = RunConfig(id: 'c', name: 'c', command: 'c', color: Color(0xFF1234AB));
        final restored = RunConfig.fromJson(cfg.toJson());
        expect(restored.color?.value, const Color(0xFF1234AB).value);
      });
    });

    group('presets', () {
      test('flutterRunMacos preset has correct command', () {
        final c = RunConfig.flutterRunMacos('/ws');
        expect(c.command, contains('flutter run'));
        expect(c.isFlutterRun, true);
        expect(c.id, 'preset_flutter_run_macos');
      });

      test('flutterTest preset', () {
        final c = RunConfig.flutterTest();
        expect(c.command, 'flutter test');
        expect(c.isFlutterRun, false);
      });

      test('flutterBuildMacos preset', () {
        final c = RunConfig.flutterBuildMacos();
        expect(c.command, contains('flutter build'));
      });

      test('flutterRunWeb preset has chrome command and hot-reload actions', () {
        final c = RunConfig.flutterRunWeb('/ws');
        expect(c.command, 'flutter run -d chrome --debug --target lib/main_web_full.dart');
        expect(c.isFlutterRun, true);
        expect(c.id, 'preset_flutter_run_web');
        expect(c.quickActions.length, 2);
      });

      test('flutterBuildWeb preset', () {
        final c = RunConfig.flutterBuildWeb();
        expect(c.command, 'flutter build web');
      });
    });

    group('Equatable', () {
      test('equal configs are equal', () {
        const a = RunConfig(id: 'a', name: 'A', command: 'cmd');
        const b = RunConfig(id: 'a', name: 'A', command: 'cmd');
        expect(a, equals(b));
      });

      test('configs with different ids are not equal', () {
        const a = RunConfig(id: 'a', name: 'A', command: 'cmd');
        const b = RunConfig(id: 'b', name: 'A', command: 'cmd');
        expect(a, isNot(equals(b)));
      });
    });
  });

  // ── RunSession ─────────────────────────────────────────────────────────────
  group('RunSession', () {
    const cfg = RunConfig(id: 'c', name: 'C', command: 'c');
    const base = RunSession(id: 's1', config: cfg, workspacePath: '/ws');

    test('default status is idle', () {
      expect(base.status, RunStatus.idle);
    });

    test('default output is empty', () {
      expect(base.output, isEmpty);
    });

    group('copyWith', () {
      test('updates status', () {
        expect(base.copyWith(status: RunStatus.running).status, RunStatus.running);
      });

      test('updates output', () {
        final line = RunOutputLine(text: 'hello', isError: false, timestamp: DateTime.now());
        expect(base.copyWith(output: [line]).output, [line]);
      });

      test('sets exitCode', () {
        expect(base.copyWith(exitCode: 0).exitCode, 0);
      });

      test('clearExitCode removes exitCode', () {
        final s = base.copyWith(exitCode: 1);
        expect(s.copyWith(clearExitCode: true).exitCode, isNull);
      });
    });

    group('Equatable', () {
      test('sessions with same id and status are equal', () {
        const a = RunSession(id: 's1', config: cfg, workspacePath: '/ws');
        const b = RunSession(id: 's1', config: cfg, workspacePath: '/ws');
        expect(a, equals(b));
      });

      test('different status means not equal', () {
        const a = RunSession(id: 's1', config: cfg, workspacePath: '/ws', status: RunStatus.idle);
        const b = RunSession(id: 's1', config: cfg, workspacePath: '/ws', status: RunStatus.running);
        expect(a, isNot(equals(b)));
      });
    });
  });

  // ── RunOutputLine ──────────────────────────────────────────────────────────
  group('RunOutputLine', () {
    test('props include text, isError, timestamp', () {
      final ts = DateTime(2025, 1, 1);
      final line = RunOutputLine(text: 'out', isError: false, timestamp: ts);
      expect(line.text, 'out');
      expect(line.isError, false);
      expect(line.timestamp, ts);
    });

    test('error line isError=true', () {
      final line = RunOutputLine(text: 'err', isError: true, timestamp: DateTime.now());
      expect(line.isError, true);
    });
  });

  // ── RunStatus enum ─────────────────────────────────────────────────────────
  group('RunStatus', () {
    test('all statuses available', () {
      expect(RunStatus.values, containsAll([
        RunStatus.idle,
        RunStatus.running,
        RunStatus.stopped,
        RunStatus.failed,
      ]));
    });
  });
}
