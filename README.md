# MonoView

An iOS photo viewer designed for people with low vision and people who use a phone with one functional hand, including people with both needs.

MonoView aims to make photo detail easier to explore without multi-finger gestures or repeated changes of grip. This is an early working prototype; accessibility and ergonomics still need evaluation with the intended users.

## Current features

- Import a photo with the system photo picker.
- View photos on a full-screen canvas, with zoom up to 20×.
- Pan with one finger, arrow controls, or optional device tilt.
- Switch to an overview and return to the previous detail position.
- Follow a four-step visual guide: welcome, explicit hand choice, a practice panel, and opening a photo.
- Use Listen for English spoken instructions and Replay for short demonstrations. Reduce Motion keeps the illustrations static.
- Move the accessibility panel by holding its grip, then dragging within a bounded envelope on the chosen side. Position is saved separately for each hand and orientation. The main panel uses icons by default, with optional captions and larger touch targets. VoiceOver labels remain available in both modes.
- Reopen the guide or reset panel positions in Settings. Reach tracing is no longer required or offered in the main setup flow.
- Adjust tilt sensitivity. While tilt is active, controls collapse to a translucent stop dot. Tap it to stop and restore the panel. Hold and drag the dot to reposition it within the bounded area; its position is saved separately for each hand and orientation. Reset panel positions resets both the panel and dot.
- In tilt mode, double-tap the photo to switch between a chosen 4×, 8× or 20× zoom and fit (1×). Sweep your thumb upward to zoom in or downward to zoom out; curved sweeps work with either hand. Tilt remains active at 1×.
- Comfort settings provide a live control preview, panel/dot opacity, opaque surfaces, position locking, zoom speed, hold duration and movement tolerance. The guide offers the same appearance preview before use. System Reduce Transparency and Increased Contrast take priority.
- Optional sound and haptic feedback, plus keeping the screen awake only while a photo is open and the app is active. Comfort settings can be reset without clearing guide progress or panel placements.
- Open Photo tools using the filter icon beside Tilt after importing a photo.
- Photo tools: non-destructive brightness, contrast, grayscale and inversion with a pinned live preview, temporary original comparison and reset. Preferences apply to later photos.
- Optional reading ruler: clear horizontal strip, adjustable height/shading, a draggable grip on the selected hand side and a position slider with VoiceOver support. Overview hides the ruler temporarily.
- Open Read text directly from the panel header (also available in Photo tools): on-device Vision recognition, large reflowed paragraphs and original-photo comparison. The reader offers text sizes and dark/light/cream pages.
- Read aloud with Pause, Resume and Stop, adjustable voice/speed, and automatic language matching with English fallback. Playback stops when leaving the reader, backgrounding the app or receiving an audio interruption.
- English interface, large-text support, VoiceOver labels and panel-movement actions. The first use of Tilt opens a separate visual gesture guide.

## Open and run

1. Open `MonoView.xcodeproj` in Xcode.
2. Select the `MonoView` scheme and an iPhone or simulator.
3. Select your development team for device signing if needed.
4. Build and run. Use a physical device to evaluate thumb reach and tilt control.

The app deployment target is iOS 17.6. Use a recent Xcode toolchain supporting the project's default actor isolation and `nonisolated` type declarations.

An unsigned device build can be checked with:

```sh
xcodebuild -project MonoView.xcodeproj -scheme MonoView \
  -configuration Release -destination 'generic/platform=iOS' \
  CODE_SIGNING_ALLOWED=NO build
```

## Project layout

- `PhotoTools.swift`: photo display filters, live preview and reading ruler geometry/interaction.
- `PhotoTextRecognition.swift`: cancellable off-main Vision work, paragraph assembly and stale-result protection.
- `PhotoReaderView.swift` and `ReaderSpeech.swift`: reflowed reader, comparison, accessible controls and speech lifecycle.
- `ContentView.swift`: viewer, persisted panel positions, guide presentation and settings.
- `MonoGuide.swift`: illustrated setup and Tilt guides, finite animations and optional speech.
- `MovablePanel.swift`: long-press positioning, geometric constraints and accessible movement actions.
- `ViewerModel.swift`: photo import, zoom, pan, overview and tilt state.
- `ReachCalibration.swift`: legacy traced-band geometry and profile types (retained for existing geometry tests).
- `ReachCalibrationView.swift`: legacy tracing view, not presented by the current guide.
- `ReachTerritoryView.swift`: custom button rendering and hit areas.
- `TiltMotionService.swift` and `TiltMath.swift`: optional sensor input and movement calculation.
- `MonoViewTests` and `MonoViewUITests`: geometry, viewer state, tilt calculations and UI flows.

## Prototype limits

- The panel positioning envelope is a conservative preset, not a measurement of an individual's comfortable reach. The guide lets users try and adjust it.
- Panel movement is initiated only from the grip; photo gestures and control taps keep their normal meaning. Existing traced layouts are retired when the new guide is completed.
- OCR uses the imported bitmap before display filters. Small print, handwriting, unsupported languages and complex columns/tables may not be recognized or ordered correctly. Compare with the photo.
- Photo decoding caps the longer dimension at 4096 pixels. Zoom enlarges existing detail; it does not create detail. Full-resolution tiled rendering is not implemented yet.
- Tilt starts off and stops on the stop dot, background transitions, Settings, viewport changes, overview, import and reset. Thumb sweeps pause sensor movement while zooming and recenter it on release. Sensor direction and comfort need physical-device testing.
- iOS Release builds, 28 unit tests and targeted UI flows (including real Vision recognition, speech Pause/Resume, empty results, original comparison and the largest Dynamic Type size) have passed. Simulator UI tests use a DEBUG-only motion stand-in to verify tilt gestures and panel transitions; real sensor behavior needs a physical device.

## Local data

The app has no account, analytics or upload workflow. Photo import uses the system picker. Preferences, guide completion and panel positions are stored locally in app preferences. The current guide does not collect thumb trails. OCR text is not saved to disk or uploaded; only reading preferences persist.
