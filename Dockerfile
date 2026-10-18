# syntax=docker/dockerfile:1.10
# check=skip=FromPlatformFlagConstDisallowed
#
# Pavex Hiện trường in one image: the Flutter web build at /, the Android APK at /download/pavex-field.apk
# and a download page (QR code, install steps) at /download/. Health check: /healthz.
#
#   docker build -t pavex/field-app .
#   docker run --rm -p 8090:8080 pavex/field-app
#
# Build args:
#   PAVEX_API_BASE_URL  API gateway the app calls (default http://localhost:8080; https://api.<domain> on staging).
#   APK_API_BASE_URL    Address baked into the APK, if phones reach the gateway differently from the browser
#                       (e.g. http://192.168.1.10:8080). Defaults to PAVEX_API_BASE_URL.
#   APK_MODE            debug (default: plain HTTP allowed, server editable on the login screen) or release
#                       (needs the upload key as build secrets, see README "Docker"; without them no APK is built).
#
# The build stage is linux/amd64 on purpose: Android's aapt2 and the Flutter Linux SDK only exist for x86_64.
# On Apple Silicon it runs emulated; the final image is a native nginx.

ARG FLUTTER_VERSION=3.44.6

FROM --platform=linux/amd64 ghcr.io/cirruslabs/android-sdk:36-ndk AS flutter
ARG FLUTTER_VERSION
# Same SDK as CI (subosito/flutter-action, flutter-version 3.44.6), checked against the release manifest's hash.
ADD --checksum=sha256:a6320fd72e9a2690c08e2a6a70874a30cb120dee7c78f49d2c628bd7c9e20525 \
    https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_${FLUTTER_VERSION}-stable.tar.xz \
    /tmp/flutter.tar.xz
ENV FLUTTER_HOME=/opt/flutter \
    PUB_CACHE=/root/.pub-cache \
    GRADLE_USER_HOME=/root/.gradle \
    FLUTTER_SUPPRESS_ANALYTICS=true \
    CI=true
ENV PATH=${FLUTTER_HOME}/bin:${PATH}
RUN (command -v xz >/dev/null || (apt-get update && apt-get install -y --no-install-recommends xz-utils && rm -rf /var/lib/apt/lists/*)) \
    && tar -xJf /tmp/flutter.tar.xz -C /opt && rm /tmp/flutter.tar.xz \
    && git config --global --add safe.directory ${FLUTTER_HOME} \
    && flutter config --no-analytics --no-cli-animations \
    && flutter precache --web --android --no-ios --no-linux --no-macos --no-windows --no-fuchsia \
    && flutter --version
# What Flutter 3.44.6 and the plugins build against (FlutterExtension.kt: compileSdk 36, NDK 28.2.13676358);
# installed here so they live in an image layer instead of being downloaded on every APK build.
RUN yes | sdkmanager --licenses >/dev/null \
    && sdkmanager --install "platforms;android-36" "build-tools;36.0.0" "ndk;28.2.13676358" >/dev/null
# The jni plugin's native build; Gradle would otherwise fetch it into the SDK on every build.
RUN sdkmanager --install "cmake;3.22.1" >/dev/null

FROM flutter AS build
WORKDIR /src
COPY pubspec.yaml pubspec.lock ./
RUN --mount=type=cache,id=pavex-field-pub,target=/root/.pub-cache \
    flutter pub get --enforce-lockfile
COPY . .

ARG PAVEX_API_BASE_URL=http://localhost:8080
RUN --mount=type=cache,id=pavex-field-pub,target=/root/.pub-cache \
    test -n "${PAVEX_API_BASE_URL}" || { echo "PAVEX_API_BASE_URL must not be empty" >&2; exit 1; }; \
    flutter build web --release --no-wasm-dry-run --dart-define=PAVEX_API_BASE_URL="${PAVEX_API_BASE_URL}" \
    && mkdir -p /out && cp -R build/web/. /out/

ARG APK_MODE=debug
ARG APK_API_BASE_URL=
ARG ANDROID_SIGNING_ALIAS=upload
# Release signing comes only from build secrets (never a build arg or a layer):
#   android_keystore           the upload keystore (.jks)
#   android_keystore_password  its password
#   android_key_password       the key's password (optional, defaults to the keystore password)
# Gradle gets a heap that fits the Docker VM (often 8 GB) instead of the project's 8 GB.
# Gradle's cache is locked per build: two builds of this image at once (compose + by hand) take turns.
RUN --mount=type=cache,id=pavex-field-pub,target=/root/.pub-cache \
    --mount=type=cache,id=pavex-field-gradle,target=/root/.gradle,sharing=locked \
    --mount=type=cache,id=pavex-field-android-debug-key,target=/root/.android,sharing=locked \
    --mount=type=secret,id=android_keystore \
    --mount=type=secret,id=android_keystore_password \
    --mount=type=secret,id=android_key_password \
    set -eu; \
    api="${APK_API_BASE_URL:-$PAVEX_API_BASE_URL}"; \
    version="$(sed -n 's/^version: *//p' pubspec.yaml)"; \
    mkdir -p /out/download; \
    info() { printf '{"version":"%s","apkMode":"%s","apkApiBaseUrl":"%s","apk":%s,"apkNote":"%s","apkBytes":%s,"apkSha256":"%s"}\n' \
      "$version" "$APK_MODE" "$api" "$1" "$2" "$3" "$4" > /out/download/build.json; }; \
    skip() { echo "==> No APK in this image: $1" >&2; info false "$1" 0 ""; }; \
    printf 'org.gradle.jvmargs=-Xmx3g -XX:MaxMetaspaceSize=1g\nkotlin.compiler.execution.strategy=in-process\n' \
      > /root/.gradle/gradle.properties; \
    case "$APK_MODE" in \
      debug) \
        flutter build apk --debug --dart-define=PAVEX_API_BASE_URL="$api"; \
        apk=build/app/outputs/flutter-apk/app-debug.apk ;; \
      release) \
        apk=""; \
        if [ ! -s /run/secrets/android_keystore ] || [ ! -s /run/secrets/android_keystore_password ]; then \
          skip "APK_MODE=release cần khoá ký (build secret android_keystore và android_keystore_password), xem README mục Docker."; \
        elif ! printf '%s' "$api" | grep -q '^https://'; then \
          skip "APK_MODE=release chỉ kết nối qua https://, nhưng địa chỉ máy chủ là $api"; \
        else \
          store_pw="$(cat /run/secrets/android_keystore_password)"; \
          key_pw="$(cat /run/secrets/android_key_password 2>/dev/null || true)"; \
          printf 'storeFile=/run/secrets/android_keystore\nstorePassword=%s\nkeyAlias=%s\nkeyPassword=%s\n' \
            "$store_pw" "$ANDROID_SIGNING_ALIAS" "${key_pw:-$store_pw}" > android/key.properties; \
          status=0; flutter build apk --release --dart-define=PAVEX_API_BASE_URL="$api" || status=$?; \
          rm -f android/key.properties; \
          [ "$status" -eq 0 ] || exit "$status"; \
          apk=build/app/outputs/flutter-apk/app-release.apk; \
        fi ;; \
      *) echo "APK_MODE must be debug or release, got \"$APK_MODE\"" >&2; exit 1 ;; \
    esac; \
    if [ -n "$apk" ]; then \
      cp "$apk" /out/download/pavex-field.apk; \
      info true "" "$(stat -c %s "$apk")" "$(sha256sum "$apk" | cut -d' ' -f1)"; \
    fi; \
    cat /out/download/build.json

FROM nginxinc/nginx-unprivileged:1.29-alpine
COPY docker/nginx.conf /etc/nginx/conf.d/default.conf
COPY --from=build /out/ /usr/share/nginx/html/
COPY docker/download/index.html /usr/share/nginx/html/download/index.html
# QR code generator for the download page (kazuhikoarase/qrcode-generator, MIT), pinned by hash.
ADD --chmod=644 --checksum=sha256:18ae399f81182bc9de916e9c77b195df20cc58d6f2d55a62b085a299f1bf1780 \
    https://cdn.jsdelivr.net/npm/qrcode-generator@1.4.4/qrcode.js /usr/share/nginx/html/download/qrcode.js
EXPOSE 8080
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s CMD wget -q -O /dev/null http://127.0.0.1:8080/healthz || exit 1
