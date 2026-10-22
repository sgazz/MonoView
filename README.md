# MonoView

An iOS photo viewer designed for people with low vision and people who use a phone with one functional hand, including people with both needs.

MonoView aims to make photo detail easier to explore without multi-finger gestures or repeated changes of grip. This is an early working prototype; accessibility and ergonomics still need evaluation with the intended users.

## Current features

- Import a photo with the system photo picker.
- View photos on a full-screen canvas, with zoom up to 20×.
- Pan with one finger, arrow controls, or optional device tilt.
- Switch to an overview and return to the previous detail position.
- Calibrate comfortable thumb reach with repeated sweeps, confirm the hand, and try a suggested layout.
- Use irregular, transparent touch regions following the traced band, with commands paginated when space is limited.
- Use manual layout settings as an alternative to calibration.
- Adjust tilt sensitivity. While tilt is active, controls collapse to a translucent stop dot. Tap it to stop and restore the panel.
- In tilt mode, double-tap the photo to switch between 20× zoom and fit (1×). Sweep your thumb upward to zoom in or downward to zoom out; curved sweeps work with either hand. Tilt remains active at 1×.
- English interface and VoiceOver labels/actions.

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

- `ContentView.swift`: viewer, control layout, setup and settings.
- `ViewerModel.swift`: photo import, zoom, pan, overview and tilt state.
- `ReachCalibration.swift`: traced-band geometry, target partitioning and saved profile.
- `ReachCalibrationView.swift`: sweep collection and layout confirmation.
- `ReachTerritoryView.swift`: custom button rendering and hit areas.
- `TiltMotionService.swift` and `TiltMath.swift`: optional sensor input and movement calculation.
- `MonoViewTests` and `MonoViewUITests`: geometry, viewer state, tilt calculations and UI flows.

## Prototype limits

- A reach trace is a layout estimate, not proof of comfortable reach or a medical assessment. Users confirm the hand and try the controls before saving.
- Fitted regions require a 57×57 pt core before rendering; tests check a 44×44 pt inner touch area. Very narrow traces fall back to manual setup.
- Calibrated layouts apply to their recorded window size and orientation. Other orientations and accessibility text sizes use the manual layout.
- Photo decoding caps the longer dimension at 4096 pixels. Zoom enlarges existing detail; it does not create detail. Full-resolution tiled rendering is not implemented yet.
- Tilt starts off and stops on the stop dot, background transitions, Settings, viewport changes, overview, import and reset. Thumb sweeps pause sensor movement while zooming and recenter it on release. Sensor direction and comfort need physical-device testing.
- iOS Release builds, 18 unit tests and targeted UI flows have passed. Simulator UI tests use a DEBUG-only motion stand-in to verify tilt gestures and panel transitions; real sensor behavior needs a physical device.

## Local data

The app has no account, analytics or upload workflow. Photo import uses the system picker. Preferences and fitted button boundaries are stored locally in app preferences; original sweep trails are not persisted.
