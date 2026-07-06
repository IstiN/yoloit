# YoLoIT GitHub Pages Demo — Current Status

> Hand-off document created: 2026-07-05
> Goal: deploy a static landing page + Flutter web demo to GitHub Pages, with all native-only features rendered as "Available in YoLoIT for macOS" placeholders.

---

## 1. What has been done

### 1.1 Landing page
- Files live in `site/`:
  - `site/index.html` — static landing page
  - `site/style.css` — styles
  - `site/yoloit_mark.svg` — logo
- Links and iframe point to `/yoloit/app/` (not `/demo/`).

### 1.2 Flutter web demo
- New web entry points:
  - `lib/main_web_full.dart`
  - `lib/app_web.dart`
- Build command (already used in CI):
  ```bash
  flutter build web --release --target lib/main_web_full.dart \
    --base-href /yoloit/app/ --pwa-strategy none
  ```
- Local build succeeds (~33–39 s). Only expected warnings remain: dart:ffi dry-run warnings from transitive unused packages.

### 1.3 Capability-based platform abstraction
- New model: `lib/core/platform/platform_capabilities*.dart` + factory.
- Generic placeholder: `lib/features/board/plugins/unsupported_capability_panel.dart`.
- Native-only plugins refactored to conditional exports (VM implementation + web stub):
  - terminal, files/filetree, diff/file preview, playlist, run configs, yolo assistant, custom widget, ui view, chat.
- Plugin type IDs decoupled into `lib/features/board/plugins/builtin/plugin_type_ids.dart`.
- Shared services/utilities adapted for web via `FileStorageAdapter`, conditional exports, or stubs:
  - theme manager, app logger, support logs, board previews, search, markdown preview, JS widget engine, widget registry, chat, etc.

### 1.4 Tests fixed
- `PlatformDirs` implementations now implement `yoloitTempDir` getter.
- Test fake `_TempPlatformDirs` classes updated.
- Plugin base classes extracted to keep `jscpd` duplication below 1 %.
- Color ratchet baselines updated for new `*_base.dart` files.
- Calendar handler/storage tests cleaned up to remove `calendar_events/` fallback artifacts between runs.

### 1.5 Commit pushed
- Commit `cfd8981` on `main` contains all of the above.

---

## 2. What is still broken / blocking deployment

### 2.1 GitHub Actions workflow fails at `flutter pub get`
Workflow `.github/workflows/deploy_demo.yml` fails because `actions/checkout@v4` does **not** fetch git submodules by default, and `pubspec.yaml` depends on:

```yaml
local_models_flutter:
  path: third_party/flutter_local_models/packages/local_models_flutter
```

Error from the failed run:
```
Because yoloit depends on local_models_flutter from path which doesn't exist
(could not find package local_models_flutter at
"third_party/flutter_local_models/packages/local_models_flutter"),
version solving failed.
```

### 2.2 Required fix (not yet committed/pushed)
Add `submodules: recursive` to the checkout step in `.github/workflows/deploy_demo.yml`:

```yaml
      - name: Checkout
        uses: actions/checkout@v4
        with:
          submodules: recursive
```

Then commit, push, and re-run the workflow.

### 2.3 Local working directory may be dirty
During the last phase the file `test/unit/core/cli/handlers/calendar_handler_test.dart` was repeatedly truncated by mistake. Before any new commit, run:

```bash
git checkout -- test/unit/core/cli/handlers/calendar_handler_test.dart
rm -rf calendar_events/
rm -f .git/index.lock
```

---

## 3. Next steps for the next developer

1. Restore clean state:
   ```bash
   git checkout -- test/unit/core/cli/handlers/calendar_handler_test.dart
   rm -rf calendar_events/
   rm -f .git/index.lock
   ```

2. Verify the workflow file is correct (only one `submodules: recursive` block):
   ```bash
   cat .github/workflows/deploy_demo.yml | head -35
   ```

3. If the fix is missing or duplicated, edit `.github/workflows/deploy_demo.yml` so the checkout step looks exactly like:
   ```yaml
       - name: Checkout
         uses: actions/checkout@v4
         with:
           submodules: recursive
   ```

4. Commit and push:
   ```bash
   git add .github/workflows/deploy_demo.yml
   git commit -m "ci: checkout submodules in deploy_demo workflow"
   git push
   ```

5. Trigger the workflow manually (or wait for push trigger):
   ```bash
   gh workflow run deploy_demo.yml
   gh run watch deploy_demo.yml
   ```

6. Verify the site loads:
   - Landing page: `https://istin.github.io/yoloit/`
   - Demo app: `https://istin.github.io/yoloit/app/`
   - Check that the landing page shows the YoLoIT brand and that the demo iframe loads the Flutter app.

---

## 4. Important architectural notes

- **No code duplication for VM/web plugin pairs**: plugin metadata lives in `*_base.dart` abstract classes; `*_vm.dart` contains only desktop content and `*_stub.dart` contains only the placeholder.
- **All desktop-only features on web** render `UnsupportedCapabilityPanel` with the message explaining they are available in the YoLoIT macOS app.
- **Do not remove `local_models_flutter` yet** unless the team explicitly decides to drop local on-device AI models. It is still imported by `local_llm_provider.dart`, `local_ai_models_service.dart`, `yolo_assistant_widget.dart`, `real_llm_tool_test_runner.dart`, etc.

---

## 5. Local verification commands

```bash
# Web build
flutter build web --release --target lib/main_web_full.dart \
  --base-href /yoloit/app/ --pwa-strategy none

# Selected tests
flutter test --no-pub \
  test/unit/features/board/ \
  test/unit/features/calendar/ \
  test/unit/features/settings/ \
  test/unit/core/platform/ \
  test/unit/core/services/ \
  test/unit/features/runs/data/run_service_test.dart \
  test/unit/core/cli/handlers/ui_handler_test.dart \
  test/unit/features/board/board_default_folder_test.dart \
  test/widget/features/board/run_configs_plugin_test.dart \
  test/widget/features/board/yolo_assistant_plugin_test.dart

# Duplication check
jscpd --min-tokens 50 --min-lines 5 lib/
```

---

## 6. Files intentionally created or modified (high-level)

New:
- `site/*`
- `lib/main_web_full.dart`, `lib/app_web.dart`
- `lib/core/platform/{platform_capabilities,file_storage_adapter,platform_dirs,platform_info}*.dart`
- `lib/features/board/plugins/board_panel_plugin_base.dart`
- `lib/features/board/plugins/builtin/*_base.dart`, `*_stub.dart`, `*_vm.dart`
- `lib/features/board/plugins/builtin/plugin_type_ids.dart`
- `lib/features/board/plugins/unsupported_capability_panel.dart`
- `lib/core/remote/board_share_server_{stub,vm}.dart`
- Conditional export web stubs for terminal, chat, preview, search, JS engine, widget registry, history store, etc.

Modified:
- `.github/workflows/deploy_demo.yml` — needs `submodules: recursive` fix
- `lib/core/platform/platform_dirs.dart`
- `lib/features/board/bloc/board_cubit.dart`
- `lib/features/calendar/data/calendar_event_storage.dart`
- `lib/core/services/app_logger.dart`, `support_log_service.dart`
- `lib/core/theme/theme_manager.dart`
- Various test files (platform dirs fakes, plugin tests, color ratchet, calendar tests)

---

## 7. Known gotchas

- The pre-commit hook enforces `jscpd < 1 %`, hardcoded-color ratchet, panel write coverage, CLI integration coverage, and full test suite. The web refactor required extracting plugin base classes to stay under the duplication threshold.
- `actions/checkout@v4` defaults to `submodules: false`; the demo workflow must explicitly enable recursive submodules.
- `calendar_events/` may be left behind by test runs; clean it before commits.
