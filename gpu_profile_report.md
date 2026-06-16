# YoLoIT GPU/Performance Profile Report

**Date:** 2026-06-16
**Build:** macOS Profile (`flutter run -d macos --profile`)
**VM Service:** http://127.0.0.1:53932/yyNJ_L0Qjrg=/
**Raw logs:**
- `/tmp/yoloit_profile_run.log`
- `/tmp/yoloit_timeline.json`

## Methodology

Timeline captured via Dart VM Service `getVMTimeline` while the user panned/zoomed the canvas.

- **UI thread** measured by `Frame` async events / `Animator::BeginFrame` on thread `io.flutter.platform` (tid 259).
- **Raster / GPU thread** measured by `GPURasterizer::Draw` on thread `io.flutter.raster` (tid 44803).

## Results

| Metric | Frames | Min | Max | Mean | p50 | p95 | p99 | >16 ms | >33 ms |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| UI Frame | 137 | 0.06 ms | 3.15 ms | 0.14 ms | 0.12 ms | 0.19 ms | 0.58 ms | 0 (0%) | 0 (0%) |
| `Animator::BeginFrame` (UI) | 137 | 0.07 ms | 3.17 ms | 0.18 ms | 0.17 ms | 0.24 ms | 0.59 ms | 0 (0%) | 0 (0%) |
| `GPURasterizer::Draw` (Raster/GPU) | 137 | 1.77 ms | 3.77 ms | 2.09 ms | 2.06 ms | 2.26 ms | 3.14 ms | 0 (0%) | 0 (0%) |

## Interpretation

- **No dropped frames:** 0% of frames exceeded 16 ms budget.
- **Raster/GPU draw time is the dominant cost** at ~2 ms mean / ~3.8 ms worst case, but still well under the 16 ms 60 FPS threshold.
- **UI thread is essentially free** during pan/zoom (~0.14 ms), meaning the recent board-layer extraction, debounce, and visibility fixes moved work off the UI thread as intended.
- The remaining GPU cost is dominated by `GPURasterizer::Draw`, i.e. the actual Metal rendering of the canvas/panels. This is expected and scales with panel count / content complexity.

## Next steps (if you want to push further)

1. **Reduce panel overdraw** — enable `RepaintBoundary` around expensive static panels and isolate the moving board background.
2. **Raster cache heavy painters** — ensure grid/minimap/shape painters set `isComplex: true` (already in guidelines; verify board code does this).
3. **Measure with Instruments Metal System Trace** to see actual GPU utilization % and command-buffer wait times if frame times ever approach 16 ms.
