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

## android, not sdkmanager

Convergence runs `android sdk install`. `sdkmanager` still works but prints a
deprecation banner on every invocation, cannot pin `emulator` or
`platform-tools` to a version, and needs a separate `--licenses` pass. The
`android` CLI takes the same `package;path` names, accepts `@<version>` on any
of them, and installs licences as it goes. `--no-metrics` opts out of the
usage reporting it does by default.

The trade is that `android` is a stub which fetches its ~235MB implementation
on first use. It caches under `$HOME/.android/cli`, so with `$HOME` bind
mounted that is one download per user, not per run; the bundle cannot be baked
into the image, as a seeded copy is re-fetched regardless of where it is
placed.

`avdmanager` stays for AVD creation: `android emulator create` only takes
coarse profiles (phone, watch, XR) and cannot name a system image.

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

## System image changes wipe AVDs

Changing the system image under an existing AVD destroys its data partition.
The emulator does this silently — no prompt, and nothing in its log naming the
wipe. It records the image's `ro.build.version.incremental` in the AVD's
`version_num.cache` and compares on each boot.

Measured with one AVD, changing one variable at a time:

| Emulator | System image | Marker in `/data/local/tmp` | userdata |
|----------|--------------|-----------------------------|----------|
| 34.1.19  | r8           | written                     | 1471 MB  |
| 37.1.11  | r8           | **survived**                | 1556 MB  |
| 37.1.11  | r14          | **gone**                    | 913 MB   |

Upgrading the emulator is safe; upgrading the system image is not. Since a
system image installs to one fixed path per SDK root, every AVD under that
root moves together when the package is upgraded — an SDK that converges to
latest will eventually wipe any AVD it inherits.

The entrypoint therefore refuses to launch an AVD whose `version_num.cache`
does not match the installed image's build, naming both builds. Pin the image
in `packages.txt` (`system-images;android-34;google_apis_playstore;x86_64@8`)
to hold an existing AVD's build; `ANDROID_ALLOW_IMAGE_CHANGE=1` accepts the
loss and proceeds.

## adb keys

The emulator injects `$HOME/.android/adbkey.pub` into the guest as it boots, so
a key generated later — by the first `adb` invocation, which is usually after
the emulator has started — is one the guest has never seen, and the device
stays `unauthorized` for that whole boot. The entrypoint generates the key
before handing over, so a pristine `$HOME` behaves like an established one.

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
