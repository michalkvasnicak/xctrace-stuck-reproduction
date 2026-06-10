# xctrace iOS App Profiling Hang Reproduction

This repository contains a minimal SwiftUI iOS app and helper script for reproducing a case where `xctrace` hangs while profiling an iOS app launch on Simulator.

The app itself is intentionally small. The important part is the workflow around building, installing, and launching it through `xctrace record` with the App Launch template.

## Reproduce

Run the reproduction script from the repository root:

```sh
./reproduce.sh
```

By default, the script selects the newest available iOS Simulator device. You can also pass a simulator UDID explicitly:

```sh
./reproduce.sh <simulator-udid>
```

The script will:

- boot the selected simulator
- build the sample app with `xcodebuild`
- install the app into the simulator
- start host and simulator log streams
- run `xcrun xctrace record --template "App Launch" --launch` against the app

Logs are written to a timestamped `repro-logs-*` directory. The trace output path is `xctrace-app-launch-repro.trace`.
