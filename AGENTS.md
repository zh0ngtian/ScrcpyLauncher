# Scrcpy Launcher

Native macOS app built with Swift 6.2+, AppKit and SwiftUI. The pinned scrcpy 4.1 client runs as an embedded dynamic library in the app's main process. See `README.md` for usage, dependencies and troubleshooting.

## Project layout

- `Sources/ScrcpyLauncher/`: application lifecycle, windows, menus and SwiftUI views.
- `Sources/ScrcpyLauncherCore/`: device discovery, preferences, command execution and scrcpy sessions.
- `Native/launcher.c`: the C bridge to the embedded scrcpy client.
- `Tests/`: Swift Testing suites and an isolated ADB/protocol fixture.
- `Scripts/`: native dependency build, app packaging and integration-test preparation. `version.env` owns the app version and build number.
- `.build/` and `dist/` are ignored build outputs; keep generated apps, downloaded dependencies and local device data out of Git.

## User interaction

- For important architectural or product decisions, always ask the user before proceeding.
- Do not make assumptions about unanswered questions.
- If user input is required, stop the current turn and wait for the next user message.
- Never implement a fallback decision without approval.

## Feishu documents

- For operations on Feishu (Lark) documents, prefer `lark-cli`.
- If `lark-cli` is not authorized or its authorization has expired, remind the user to authorize or reauthorize it before proceeding.

## Implementation boundaries

- Connect only to the saved device serial. An offline or unauthorized device must not erase the selection or silently select another device.
- Preserve bundle identifier `dev.playphone.ScrcpyLauncher` and preference keys `defaultDeviceSerial` / `defaultDeviceName` when upgrading.
- Keep the scrcpy/SDL session on the application's main thread. Stop the previous session before switching devices; never stop the shared ADB server.
- Keep the client, matching server and non-system dynamic libraries inside the app bundle. Runtime discovery of local tools is for ADB; do not depend on an installed scrcpy executable.
- Keep upstream downloads pinned and SHA-256 verified in `Scripts/build_client.sh`; upstream patches must fail if their expected source does not match.

## Validation

- Run `swift test` for core behavior. Building the Swift executable alone does not produce a runnable app with the native resources.
- When changing native integration or window/menu behavior, package the app first, then use `PATH="/opt/homebrew/bin:$PATH" python3 Scripts/prepare_integration_test.py` for the isolated integration app described in `README.md`.
- Keep integration tests isolated from production device preferences and real devices.

## Build and installation

- After completing changes and appropriate validation, build the latest app with `Scripts/package_app.sh` and install it directly to `/Applications/Scrcpy Launcher.app`, without asking for confirmation again.
- Packaging creates `dist/Scrcpy Launcher.app`; `Scripts/launch.sh` opens that build and does not install it. The native build supports only the host architecture; the packaged minimum macOS version follows its bundled libraries.
- If the installed app is running, quit it gracefully before replacement and reopen it after installation so the running app uses the updated build.
- Verify the installed app's signature and that its contents and `GitCommit` / `BuildTimestamp` match the latest build. Preserve the user's device preferences.
