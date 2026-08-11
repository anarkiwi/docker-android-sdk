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
        yes | sdkmanager --sdk_root="${ANDROID_SDK_ROOT}" --licenses >/dev/null
        # shellcheck disable=SC2086
        sdkmanager --sdk_root="${ANDROID_SDK_ROOT}" ${packages}
        printf '%s\n' "${want}" >"${marker}"
    fi
fi

exec "$@"
