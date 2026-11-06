# Startup recording — 4 November 2026

Simulator: iPhone 18 Pro, iOS 27.2. Existing app data and cached map tiles retained.
Mobile Dev triggered relaunch. Its screen recorder failed with a process-ownership error and an empty video, so XcodeBuildMCP recorded the same simulator instead.

Final video: simulator-launch.mp4. Sampled frames: launch-frames.png.
Approximate positions in the recording: startup UI at 0.6 s; native loading indicator remains animated while the local SVG loads; visible SVG expansion at 2.0–2.4 s; map visible at 2.6 s and loader gone around 2.8 s.
These are recording-relative times, not instrumented cold-launch measurements. The reported two-minute physical-device delay was not reproduced and remains unverified.

Changes: defer construction of the large app hierarchy until the initial loading hierarchy can paint; keep one SVG view mounted; remove initial SVG opacity hiding; wait two WebKit animation frames before signaling readiness; retain the SVG for a short 300 ms visible interval; use a bounded startup fallback. Correct city annotation child coordinates and separate city bubbles from coordinate dots by 6 points.

Final simulator build and launch succeeded without warnings or errors.

## Native renderer revision

The runtime WKWebView loader was removed after physical-device logs showed slow process startup and rendering-context failures. `scripts/render_loading_animation.py` bakes a short forward/reverse excerpt of the supplied SVG's SMIL timeline into `Brand/loading-native.png` (about 158 KB). UIKit plays it; Reduce Motion shows the matching still. The system launch screen and app loader use matching centered artwork and sizing, with no extra subtitle or spinner stages.

`native-loading.mp4` and `native-loading-frames.png` capture the revision on Simulator. Native artwork changes are visible before the map appears. This is not a physical-device launch benchmark.

City counter icons now use aspect-fit UIImageViews and the valid `mappin` symbol instead of stretching text attachments.

The iPhone 13 Pro was discovered and the app opened through Mobile Dev, but CPU attachment failed (development signing/get-task-allow or active debugger), and UI runner attachment reported macOS DevToolsSecurity disabled. No physical-device CPU samples were collected. The reported 90-second delay remains unverified.
