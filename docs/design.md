# Design

## Thin image, host SDK

The image carries only the JDK, Google's `cmdline-tools`, and the shared
libraries the emulator's bundled Qt and qemu `dlopen`. Everything Google ships
per-version — `platform-tools`, `emulator`, system images — is installed by the
entrypoint into the bind mounted SDK directory.

- The image stays ~500 MB rather than several GB, and rebuilds do not re-fetch
  multi-GB system images.
- Nothing under the Android SDK licence is redistributed in a published layer.
- AVD state is large (tens to hundreds of GB of qcow2) and belongs on the host.
- Upgrading the SDK is an edit to `packages.txt`, not an IDE session.

`platform-tools` and `emulator` have no version selector in `sdkmanager`; it
installs the current stable channel build. Pinning those exactly would mean
fetching the zips directly, which is not worth the maintenance.

## cmdline-tools is mirrored, not installed

`sdkmanager` and `avdmanager` locate the SDK from their own install path and
ignore `$ANDROID_SDK_ROOT`; run from outside a `<sdk>/cmdline-tools/latest`
layout they fail with "Could not determine SDK root", and `avdmanager` then
reports every system image path as invalid. `sdkmanager` also silently skips
`cmdline-tools;latest` in a package list, because that is the package it is
itself running from.

So the entrypoint copies the image's `cmdline-tools` into
`$ANDROID_SDK_ROOT/cmdline-tools/latest`, refreshing it whenever the image's
`source.properties` differs. Every tool then resolves the root unaided,
including on the host outside the container. The image is the source of truth
for that package; `sdkmanager` owns the rest.

## No baked-in user

The image creates no user and sets no `HOME`. `bin/android-sdk` passes
`--user "$(id -u):$(id -g)"`, `-e HOME`, and bind mounts `$HOME` at the same
path, plus `/etc/passwd` and `/etc/group` read-only so name lookups resolve.
Files the container writes are owned by the caller, and absolute paths already
recorded in AVD `config.ini` (for example `skin.path`) keep resolving.

Bind mounting all of `$HOME` is deliberate: the container is a packaging
mechanism for the SDK, not a sandbox, and it removes any guessing about which
dotfiles the emulator touches. Narrow it to `$HOME/.android` and
`$ANDROID_SDK_ROOT` if isolation matters more than fidelity.

## Emulator launcher, not qemu

Invoke `emulator`, not `qemu-system-x86_64` directly. The launcher resolves the
system image, skin, GPU backend and library paths itself; calling qemu directly
requires a hand-built `LD_LIBRARY_PATH` and forces `-gpu off`, which modern
emulator builds do not support. `-gpu swiftshader_indirect` is the portable
default; `-gpu host` works where `/dev/dri` is passed through.

## KVM and VirtualBox

The emulator needs `/dev/kvm`, and VirtualBox cannot share VMX root with KVM.
The wrapper loads `kvm_intel`/`kvm_amd` only when `/dev/kvm` is absent and
unloads it from an `EXIT` trap, so an emulator crash cannot leave the module
loaded and VirtualBox broken. Docker resolves `--device` at container create,
so the module must be loaded on the host first — it cannot move into the image.

`--group-add` for `kvm`, `render`, `video` and `audio` plus explicit `--device`
flags replace the `--privileged` that GUI container wrappers often use.

The wrapper does not `exec docker run` when it loaded the module: `exec`
replaces the shell and takes the `EXIT` trap with it, which is the failure the
trap exists to prevent.

## XDG_RUNTIME_DIR

The emulator registers each running instance under `$XDG_RUNTIME_DIR`, and
PulseAudio's socket lives there, so the wrapper mounts the caller's runtime
directory whole rather than cherry-picking the audio socket. Without it the
emulator falls back to `/run/user/<uid>`, which does not exist in the
container, and aborts before the guest starts. When the caller has no runtime
directory (CI, cron) the entrypoint falls back to `$HOME/.android/run`.

## Networking

`--network host` so the emulator's adb ports (5554/5555) appear exactly where a
host `adb` expects them, and `--ipc host` so X11 MIT-SHM works — the default
64 MB `/dev/shm` is not enough for Qt.
