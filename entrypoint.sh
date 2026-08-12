#!/bin/sh
# Converge the bind mounted SDK to the pinned package list, then exec the
# requested tool. Convergence is a no-op once the package list is satisfied.
set -e

: "${HOME:?HOME must be set (pass -e HOME and bind mount it)}"
: "${ANDROID_SDK_ROOT:=${HOME}/Android/Sdk}"
: "${ANDROID_PACKAGES_FILE:=/etc/android-packages.txt}"
: "${ANDROID_SDK_SYNC:=1}"
# The emulator writes its registration directory here. Fall back to somewhere
# writable when the caller has no runtime directory to share (CI, cron).
: "${XDG_RUNTIME_DIR:=${HOME}/.android/run}"
mkdir -p "${XDG_RUNTIME_DIR}"
chmod 700 "${XDG_RUNTIME_DIR}"
export XDG_RUNTIME_DIR

ANDROID_HOME="${ANDROID_SDK_ROOT}"
PATH="${ANDROID_SDK_ROOT}/emulator:${ANDROID_SDK_ROOT}/platform-tools:${ANDROID_SDK_ROOT}/cmdline-tools/latest/bin:${PATH}"
export ANDROID_HOME ANDROID_SDK_ROOT PATH

if [ "${ANDROID_SDK_SYNC}" != "0" ]; then
    mkdir -p "${ANDROID_SDK_ROOT}/cmdline-tools" "${HOME}/.android"

    # sdkmanager and avdmanager locate the SDK from their own install path and
    # ignore $ANDROID_SDK_ROOT, and sdkmanager will not install the package it
    # is itself running from. Mirror the image's copy into the canonical
    # <sdk>/cmdline-tools/latest so every tool resolves the root unaided.
    tools=/opt/android-cmdline-tools/latest
    installed="${ANDROID_SDK_ROOT}/cmdline-tools/latest"
    if ! cmp -s "${tools}/source.properties" "${installed}/source.properties"; then
        rm -rf "${installed}.new"
        cp -a "${tools}" "${installed}.new"
        rm -rf "${installed}"
        mv "${installed}.new" "${installed}"
    fi

    marker="${ANDROID_SDK_ROOT}/.packages.sha256"
    want="$(sha256sum "${ANDROID_PACKAGES_FILE}" | cut -d' ' -f1)"
    if [ "${want}" != "$(cat "${marker}" 2>/dev/null || true)" ]; then
        packages="$(sed -e 's/#.*//' -e '/^[[:space:]]*$/d' "${ANDROID_PACKAGES_FILE}")"
        # shellcheck disable=SC2086
        android --no-metrics --sdk "${ANDROID_SDK_ROOT}" sdk install ${packages}

        # A package it cannot resolve - an unpublished system image revision,
        # say - is reported as "Ignoring" and skipped, and the install still
        # exits 0, having created the empty directory tree. Every installed
        # package carries a source.properties, so check for that.
        missing=
        for package in ${packages}; do
            path="$(printf '%s' "${package%@*}" | tr ';' '/')"
            [ -f "${ANDROID_SDK_ROOT}/${path}/source.properties" ] ||
                missing="${missing} ${package}"
        done
        if [ -n "${missing}" ]; then
            echo "convergence incomplete, not installed:${missing}" >&2
            exit 1
        fi

        printf '%s\n' "${want}" >"${marker}"
    fi
fi

# The emulator injects $HOME/.android/adbkey.pub into the guest as it boots. A
# key generated later - by the first adb invocation - is one the guest has
# never seen, and the device stays "unauthorized" for the life of that boot.
if [ ! -f "${HOME}/.android/adbkey" ] && command -v adb >/dev/null 2>&1; then
    adb keygen "${HOME}/.android/adbkey" >/dev/null 2>&1 || true
fi

# The emulator wipes an AVD's data partition, silently and without prompting,
# when the installed system image's build differs from the one the AVD was
# provisioned against. It records that build in the AVD's version_num.cache.
# Refuse the launch instead; ANDROID_ALLOW_IMAGE_CHANGE=1 accepts the wipe.
if [ "$1" = "emulator" ] && [ "${ANDROID_ALLOW_IMAGE_CHANGE:-0}" != "1" ]; then
    avd=
    prev=
    for arg in "$@"; do
        [ "${prev}" = "-avd" ] && avd="${arg}"
        case "${arg}" in @?*) avd="${arg#@}" ;; esac
        prev="${arg}"
    done

    avd_home="${ANDROID_AVD_HOME:-${HOME}/.android/avd}"
    avd_dir="$(sed -n 's/^path=//p' "${avd_home}/${avd:-.}.ini" 2>/dev/null)"
    provisioned="$(cat "${avd_dir}/version_num.cache" 2>/dev/null || true)"
    sysdir="$(sed -n 's/^image.sysdir.1=//p' "${avd_dir}/config.ini" 2>/dev/null || true)"
    installed_build="$(sed -n 's/^ro.build.version.incremental=//p' \
        "${ANDROID_SDK_ROOT}/${sysdir}build.prop" 2>/dev/null || true)"

    if [ -n "${provisioned}" ] && [ -n "${installed_build}" ] &&
       [ "${provisioned}" != "${installed_build}" ]; then
        cat >&2 <<MSG
refusing to launch ${avd}: its system image has changed

  provisioned against build ${provisioned}
  installed system image is build ${installed_build}
  (${ANDROID_SDK_ROOT}/${sysdir})

Booting would wipe this AVD's data partition, without warning. Install the
build it expects, point ANDROID_SDK_ROOT at an SDK that has it, or set
ANDROID_ALLOW_IMAGE_CHANGE=1 to accept losing the data.
MSG
        exit 1
    fi
fi

exec "$@"
