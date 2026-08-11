#!/bin/sh
# Converge the bind mounted SDK to the pinned package list, then exec the
# requested tool. Convergence is a no-op once the package list is satisfied.
set -e

: "${HOME:?HOME must be set (pass -e HOME and bind mount it)}"
: "${ANDROID_SDK_ROOT:=${HOME}/Android/Sdk}"
: "${ANDROID_PACKAGES_FILE:=/etc/android-packages.txt}"
: "${ANDROID_SDK_SYNC:=1}"

ANDROID_HOME="${ANDROID_SDK_ROOT}"
PATH="${ANDROID_SDK_ROOT}/emulator:${ANDROID_SDK_ROOT}/platform-tools:${ANDROID_SDK_ROOT}/cmdline-tools/latest/bin:${PATH}"
export ANDROID_HOME ANDROID_SDK_ROOT PATH

if [ "${ANDROID_SDK_SYNC}" != "0" ]; then
    mkdir -p "${ANDROID_SDK_ROOT}" "${HOME}/.android"
    marker="${ANDROID_SDK_ROOT}/.packages.sha256"
    want="$(sha256sum "${ANDROID_PACKAGES_FILE}" | cut -d' ' -f1)"
    if [ "${want}" != "$(cat "${marker}" 2>/dev/null || true)" ]; then
        packages="$(sed -e 's/#.*//' -e '/^[[:space:]]*$/d' "${ANDROID_PACKAGES_FILE}")"
        # The image's copy only bootstraps: it resolves no SDK root of its own,
        # hence --sdk_root. packages.txt installs cmdline-tools into the SDK,
        # after which every tool resolves the root from its own location.
        bootstrap=/opt/android-cmdline-tools/latest/bin/sdkmanager
        yes | "${bootstrap}" --sdk_root="${ANDROID_SDK_ROOT}" --licenses >/dev/null
        # shellcheck disable=SC2086
        "${bootstrap}" --sdk_root="${ANDROID_SDK_ROOT}" ${packages}
        printf '%s\n' "${want}" >"${marker}"
    fi
fi

exec "$@"
