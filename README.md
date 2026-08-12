# docker-android-sdk

Android SDK command line tools and emulator in a container, driving the SDK and
AVDs in `$HOME` on the host.

## Use

```sh
bin/android-sdk                             # list AVDs
bin/android-sdk emulator -avd virtual7      # run an AVD
bin/android-sdk adb devices
bin/android-sdk avdmanager list target
bin/android-sdk android sdk list             # installed packages
bin/wait-for-boot                           # block until a booting AVD is up
```

The first run installs the packages in [packages.txt](packages.txt) into
`$ANDROID_SDK_ROOT` (default `$HOME/Android/Sdk`); later runs are a no-op until
that file changes. `bin/android-sdk` bind mounts `$HOME` at the same path, runs
as the calling uid/gid, and passes through KVM, `/dev/dri`, X11 and PulseAudio
when present. The emulator needs KVM, so the wrapper `modprobe`s it (via
`sudo`) if absent and unloads it on exit.

## Build

```sh
docker build -t anarkiwi/android-sdk .
```

## Configure

| Variable | Default | Purpose |
|----------|---------|---------|
| `ANDROID_SDK_IMAGE` | `anarkiwi/android-sdk:latest` | Image to run |
| `ANDROID_SDK_ROOT` | `$HOME/Android/Sdk` | SDK location on the host |
| `ANDROID_SDK_SYNC` | `1` | `0` skips package convergence |
| `ANDROID_PACKAGES_FILE` | `/etc/android-packages.txt` | Package list in the container |
| `ANDROID_SDK_DOCKER_ARGS` | | Extra `docker run` arguments |

## Docs

- [docs/design.md](docs/design.md) — what is in the image and what is not, and why.
