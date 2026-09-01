FROM eclipse-temurin:25.0.2_10-jdk-jammy

ARG ANDROID_CMDLINE_TOOLS_VERSION=13114758
ARG ANDROID_COMPILE_PLATFORM=35
ARG ANDROID_BUILD_TOOLS_VERSION=36.0.0
ARG ANDROID_EMULATOR_PLATFORM=37.0
ARG ANDROID_PLATFORM_TOOLS_VERSION=37.0.1
ARG ANDROID_EMULATOR_VERSION=37.2.7
ARG ANDROID_COMPILE_PLATFORM_REVISION=2
ARG ANDROID_SYSTEM_IMAGE_REVISION=6

ENV ANDROID_HOME=/opt/android-sdk \
    ANDROID_SDK_ROOT=/opt/android-sdk \
    PATH=/opt/android-sdk/cmdline-tools/latest/bin:/opt/android-sdk/platform-tools:/opt/android-sdk/emulator:$PATH

RUN apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get install --yes --no-install-recommends \
        ca-certificates curl libasound2 libnss3 libpulse0 libx11-xcb1 \
        libxcomposite1 libxkbcommon-x11-0 novnc openbox unzip websockify \
        x11vnc xvfb \
    && rm -rf /var/lib/apt/lists/*

RUN mkdir -p "$ANDROID_HOME/cmdline-tools" \
    && curl --fail --location --show-error \
        "https://dl.google.com/android/repository/commandlinetools-linux-${ANDROID_CMDLINE_TOOLS_VERSION}_latest.zip" \
        --output /tmp/command-line-tools.zip \
    && unzip -q /tmp/command-line-tools.zip -d /tmp/android-command-line-tools \
    && mv /tmp/android-command-line-tools/cmdline-tools "$ANDROID_HOME/cmdline-tools/latest" \
    && rm -rf /tmp/command-line-tools.zip /tmp/android-command-line-tools \
    && yes | sdkmanager --licenses >/dev/null \
    && sdkmanager --channel=3 --install \
        "platform-tools" \
        "emulator" \
        "platforms;android-${ANDROID_COMPILE_PLATFORM}" \
        "build-tools;${ANDROID_BUILD_TOOLS_VERSION}" \
        "system-images;android-${ANDROID_EMULATOR_PLATFORM};google_apis;x86_64" \
    && grep -H '^Pkg.Revision=' \
        "$ANDROID_HOME/platform-tools/source.properties" \
        "$ANDROID_HOME/emulator/source.properties" \
        "$ANDROID_HOME/platforms/android-${ANDROID_COMPILE_PLATFORM}/source.properties" \
        "$ANDROID_HOME/system-images/android-${ANDROID_EMULATOR_PLATFORM}/google_apis/x86_64/source.properties" \
    && grep -Fqx "Pkg.Revision=${ANDROID_PLATFORM_TOOLS_VERSION}" "$ANDROID_HOME/platform-tools/source.properties" \
    && grep -Fqx "Pkg.Revision=${ANDROID_EMULATOR_VERSION}" "$ANDROID_HOME/emulator/source.properties" \
    && grep -Fqx "Pkg.Revision=${ANDROID_COMPILE_PLATFORM_REVISION}" "$ANDROID_HOME/platforms/android-${ANDROID_COMPILE_PLATFORM}/source.properties" \
    && grep -Fqx "Pkg.Revision=${ANDROID_SYSTEM_IMAGE_REVISION}" "$ANDROID_HOME/system-images/android-${ANDROID_EMULATOR_PLATFORM}/google_apis/x86_64/source.properties" \
    && chmod -R a+rX "$ANDROID_HOME"

WORKDIR /workspace
