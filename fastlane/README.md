fastlane documentation
----

# Installation

Make sure you have the latest version of the Xcode command line tools installed:

```sh
xcode-select --install
```

For _fastlane_ installation instructions, see [Installing _fastlane_](https://docs.fastlane.tools/#installing-fastlane)

# Available Actions

## iOS

### ios generate

```sh
[bundle exec] fastlane ios generate
```

Regenerate Strand.xcodeproj from project.yml (XcodeGen is the source of truth)

### ios bump

```sh
[bundle exec] fastlane ios bump
```

Bump the build number (CURRENT_PROJECT_VERSION) in project.yml, then regenerate the project

### ios setup_signing

```sh
[bundle exec] fastlane ios setup_signing
```

Create Bundle IDs and enable capabilities needed by automatic signing

### ios setup_app

```sh
[bundle exec] fastlane ios setup_app
```

Create Bundle IDs/capabilities and the App Store Connect app record (run once; safe to re-run)

### ios beta

```sh
[bundle exec] fastlane ios beta
```

Build a Release archive and upload it to TestFlight

----

This README.md is auto-generated and will be re-generated every time [_fastlane_](https://fastlane.tools) is run.

More information about _fastlane_ can be found on [fastlane.tools](https://fastlane.tools).

The documentation of _fastlane_ can be found on [docs.fastlane.tools](https://docs.fastlane.tools).
