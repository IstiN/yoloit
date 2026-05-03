# Dependency Upgrade Blockers

Generated: 2026-05-01  
Tool: `flutter pub outdated` + `flutter pub deps --json`

**Key finding:** `flutter pub outdated` reports `Resolvable = Current` for ALL 14 blocked transitive
packages. This means there is no version of any of them that satisfies the current full constraint set.
Each blocked package is pinned by one or more direct or SDK-level dependencies.

---

## Summary Table

| Package | Current → Latest | Kind | Blocked by | Action |
|---|---|---|---|---|
| `flutter_markdown` | 0.7.7+1 (discontinued) | direct main | — (owned by project) | ✅ Replaced with `flutter_markdown_plus 1.0.7` |
| `golden_toolkit` | 0.15.0 (discontinued) | direct dev | — (owned by project) | ⚠️ Needs test migration (see below) |
| `vector_math` | 2.2.0 → 2.3.0 | direct main | **Flutter SDK** pins 2.2.x | ❌ Blocked by SDK |
| `analyzer` | 10.0.1 → 13.0.0 | transitive dev | `bloc_test ^10` → `test ^1.30` → `analyzer ^10` | ❌ Blocked by `bloc_test` |
| `_fe_analyzer_shared` | 93.0.0 → 100.0.0 | transitive dev | Ships with `analyzer` | ❌ Blocked by `analyzer` |
| `test` | 1.30.0 → 1.31.1 | transitive dev | `bloc_test ^10` (and Flutter SDK `test_api` ceiling) | ❌ Blocked by `bloc_test` + SDK |
| `test_core` | 0.6.16 → 0.6.18 | transitive dev | `test 1.30` | ❌ Blocked by `test` |
| `test_api` | 0.7.10 → 0.7.12 | transitive dev | Flutter SDK + `test 1.30` | ❌ Blocked by SDK |
| `matcher` | 0.12.19 → 0.12.20 | transitive | Flutter SDK + `test 1.30` + `xterm` | ❌ Blocked by SDK |
| `meta` | 1.17.0 → 1.18.2 | transitive | Flutter SDK (bundled) | ❌ Blocked by SDK |
| `device_info_plus` | 11.5.0 → 13.1.0 | transitive | `super_clipboard ^0.9.1` → `super_native_extensions` | ❌ Blocked by `super_clipboard` |
| `device_info_plus_platform_interface` | 7.0.3 → 8.1.0 | transitive | `device_info_plus 11.5` | ❌ Blocked by `device_info_plus` |
| `win32` | 5.15.0 → 6.1.0 | transitive | `file_picker ^11`, `flutter_secure_storage ^10`, `super_clipboard ^0.9.1` | ❌ Blocked by 3 direct deps |
| `win32_registry` | 2.1.0 → 3.0.3 | transitive | `super_clipboard` → `super_native_extensions` → `device_info_plus` | ❌ Blocked by `super_clipboard` |
| `native_toolchain_c` | 0.17.6 → 0.18.0 | transitive | `flutter_secure_storage ^10` → `objective_c` | ❌ Blocked by `flutter_secure_storage` |
| `xml` | 6.6.1 → 7.0.1 | transitive | `flutter_svg ^2.2.4` → `vector_graphics_compiler ^1.2` | ❌ Blocked by `flutter_svg` |

---

## Reverse Dependency Chains

### Testing cluster (blocked by `bloc_test` + Flutter SDK)

```
_fe_analyzer_shared 93 (→100)
  ← analyzer 10 (→13)
       ← test 1.30 (→1.31.1)
            ← bloc_test 10.0.0   [direct dev dep in pubspec.yaml]

analyzer 10 (→13)
  ← test 1.30
       ← bloc_test 10.0.0   [direct dev]

test 1.30 (→1.31.1)
  ← bloc_test 10.0.0   [direct dev]

test_core 0.6.16 (→0.6.18)
  ← test 1.30
       ← bloc_test 10.0.0   [direct dev]

test_api 0.7.10 (→0.7.12)
  ← flutter_test [Flutter SDK dev]  ← Flutter SDK ceiling
  ← test 1.30 ← bloc_test 10.0.0  [direct dev]

matcher 0.12.19 (→0.12.20)
  ← flutter_test [Flutter SDK dev]  ← Flutter SDK ceiling
  ← test 1.30 ← bloc_test 10.0.0  [direct dev]
  ← quiver ← xterm (local package)  [direct main]
```

**How to unblock:** Upgrade `bloc_test` to a major version that ships with `test >=1.31`.
Currently `bloc_test ^10.0.0` is the newest `bloc_test` version. No newer major available.
`flutter pub outdated` reports dev_dependencies "all up-to-date".
Additionally, the Flutter SDK itself constrains `test_api` and `matcher`.
**Ultimately: wait for Flutter SDK upgrade or bloc_test major release.**

---

### Windows platform cluster (blocked by `super_clipboard`)

```
device_info_plus 11.5 (→13.1)
  ← super_native_extensions 0.9.1
       ← super_clipboard 0.9.1   [direct main dep in pubspec.yaml]

device_info_plus_platform_interface 7.0.3 (→8.1)
  ← device_info_plus 11.5
       ← (chain above)

win32 5.15 (→6.1)
  ← file_picker 11.0.2           [direct main dep]
  ← flutter_secure_storage_windows ← flutter_secure_storage 10.0.0  [direct main]
  ← super_native_extensions 0.9.1 ← super_clipboard 0.9.1  [direct main]

win32_registry 2.1.0 (→3.0.3)
  ← device_info_plus 11.5
       ← super_native_extensions 0.9.1
            ← super_clipboard 0.9.1   [direct main]
```

**How to unblock:** Upgrade `super_clipboard` to a version that ships `super_native_extensions`
with `device_info_plus >=12` and `win32 >=6`. Currently `^0.9.1` is the newest resolvable.
`flutter pub outdated` reports direct deps "all up-to-date" for `super_clipboard`.
**Ultimately: wait for `super_clipboard`/`super_native_extensions` to release updated transitive deps.**

---

### Build toolchain (blocked by `flutter_secure_storage`)

```
native_toolchain_c 0.17.6 (→0.18.0)
  ← objective_c 9.3.0
       ← path_provider_foundation
            ← path_provider
                 ← flutter_secure_storage_windows
                      ← flutter_secure_storage 10.0.0   [direct main dep]
```

**How to unblock:** `flutter_secure_storage ^10.0.0` is at its latest. Needs a new major
release that updates the `objective_c` → `native_toolchain_c` chain.

---

### SVG/markup toolchain (blocked by `flutter_svg`)

```
xml 6.6.1 (→7.0.1)
  ← vector_graphics_compiler 1.2.0
       ← flutter_svg 2.2.4   [direct main dep]
  ← dbus 0.7.12
       ← file_picker 11.0.2  [direct main dep]
```

**How to unblock:** `flutter_svg ^2.2.4` must release a version that bumps
`vector_graphics_compiler` to use `xml ^7.0.0`.

---

### SDK-pinned (nothing to do)

```
vector_math 2.2.0 (→2.3.0)
  ← flutter [Flutter SDK]         ← SDK determines ceiling
  ← flutter_test [Flutter SDK dev]

meta 1.17.0 (→1.18.2)
  ← flutter [Flutter SDK]         ← bundled with SDK
  ← virtually every package in the tree
```

**How to unblock:** Flutter SDK upgrade. No pubspec.yaml change can help.

---

## Directly actionable items

### ✅ Done: `flutter_markdown` → `flutter_markdown_plus 1.0.7`
Drop-in replacement. Same `Markdown`, `MarkdownBody`, `MarkdownStyleSheet` API.
Changed: `pubspec.yaml` + 2 import statements.

### ⚠️ Pending: `golden_toolkit` migration
`golden_toolkit 0.15.0` is discontinued but its latest IS 0.15.0, so `flutter pub outdated`
doesn't flag it. The package still works — removal is hygiene, not a functional fix.

**Note:** Removing `golden_toolkit` does NOT unblock `analyzer`/`test` upgrades, because
`bloc_test` independently constrains the same chain to the same ceiling.

Migration needed in 2 files:
- `test/flutter_test_config.dart` — `loadAppFonts()` → custom font loader
- `test/golden/panel_goldens_test.dart` — `pumpWidgetBuilder(w)` → `tester.pumpWidget(MaterialApp(home: w))`

Best replacement: **`alchemist`** package (same golden-test philosophy, actively maintained)
or native `flutter_test` goldens directly.

---

## Nothing else to do until ecosystem catches up

The remaining 12 transitive packages cannot be unblocked by any change to **this project's**
`pubspec.yaml`. They require upstream releases from `super_clipboard`, `file_picker`,
`flutter_svg`, `flutter_secure_storage`, and the Flutter SDK itself.

Monitor with: `flutter pub outdated` after any Flutter SDK upgrade or `flutter pub upgrade`.
