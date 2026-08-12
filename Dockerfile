# Android SDK tooling image.
#
# The image carries the JDK, the emulator's runtime libraries and Google's
# command line tools. The SDK payload (platform-tools, emulator, system
# images) and all AVD state live in a bind mounted host directory, so the
# image stays small and redistributes none of Google's SDK.
#
# Runs as whatever --user is passed; no user is baked in. HOME, and therefore
# ANDROID_SDK_ROOT ($HOME/Android/Sdk by default), come from the environment.

FROM debian:trixie-slim AS tools

ARG CMDLINE_TOOLS_BUILD=15859902
ARG CMDLINE_TOOLS_SHA1=040d3996a65543d22ec4bf73e4c37aa37a8d4af4

# hadolint ignore=DL3008
RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates curl unzip \
    && rm -rf /var/lib/apt/lists/* \
    && curl -fsSLO "https://dl.google.com/android/repository/commandlinetools-linux-${CMDLINE_TOOLS_BUILD}_latest.zip" \
    && printf '%s  commandlinetools-linux-%s_latest.zip\n' "${CMDLINE_TOOLS_SHA1}" "${CMDLINE_TOOLS_BUILD}" >sha1sums \
    && sha1sum -c sha1sums \
    && unzip -q "commandlinetools-linux-${CMDLINE_TOOLS_BUILD}_latest.zip" -d /opt \
    && mkdir -p /opt/android-cmdline-tools \
    && mv /opt/cmdline-tools /opt/android-cmdline-tools/latest \
    && rm -f "commandlinetools-linux-${CMDLINE_TOOLS_BUILD}_latest.zip"

FROM debian:trixie-slim AS runtime

ENV DEBIAN_FRONTEND=noninteractive

# openjdk: sdkmanager/avdmanager. The rest is what the emulator's bundled Qt
# and qemu dlopen at runtime; the emulator ships its own Qt in the SDK.
# hadolint ignore=DL3008
RUN apt-get update && apt-get install -y --no-install-recommends \
        default-jre-headless \
        libasound2t64 \
        libdbus-1-3 \
        libegl1 \
        libfontconfig1 \
        libfreetype6 \
        libgl1 \
        libglx-mesa0 \
        libice6 \
        libnss3 \
        libpulse0 \
        libsm6 \
        libvulkan1 \
        libx11-xcb1 \
        libxcb-cursor0 \
        libxcb-icccm4 \
        libxcb-image0 \
        libxcb-keysyms1 \
        libxcb-randr0 \
        libxcb-render-util0 \
        libxcb-shape0 \
        libxcb-xinerama0 \
        libxcb-xkb1 \
        libxcomposite1 \
        libxdamage1 \
        libxi6 \
        libxkbcommon-x11-0 \
        libxkbfile1 \
        libxrandr2 \
        libxtst6 \
        mesa-va-drivers \
        mesa-vulkan-drivers \
    && rm -rf /var/lib/apt/lists/*

COPY --from=tools /opt/android-cmdline-tools /opt/android-cmdline-tools
COPY packages.txt /etc/android-packages.txt
COPY entrypoint.sh /usr/local/bin/entrypoint.sh

ENV PATH=/opt/android-cmdline-tools/latest/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["emulator", "-list-avds"]
