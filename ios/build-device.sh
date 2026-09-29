#!/usr/bin/env sh
# Build the SDL renderer for iPhone, sign it with the given provisioning profile and package it as an .ipa.
#
# The native libraries (SDL3, miniaudio, stb, pffft, pa_ringbuffer) are rebuilt for the device once,
# into external/ios-device. Odin only emits an object file, clang links it into the app bundle.
#
#   IOS_PROFILE=<path>        provisioning profile, required, the bundle id and entitlements come from it
#   IOS_SIGN_IDENTITY=<name>  signing certificate, defaults to "Apple Development" for a development profile
#                             (e.g. a free Personal Team) and "Apple Distribution" for an Ad Hoc one
#   IOS_DEVICE=<name or udid> installs and launches the app on this iPhone, needs Developer Mode on it
#   SDL_VERSION=3.2.x         SDL release to build, defaults to the brew installed version
#
# An Ad Hoc .ipa also installs without Developer Mode, by dragging it onto the iPhone in Finder.

set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
DEPS="$ROOT/external/ios-device"
OUT="$ROOT/build/ios-device"
APP="$OUT/Payload/StrobeTuner.app"
IPA="$OUT/SonicStrobe.ipa"
MIN_IOS=15.0
TARGET="arm64-apple-ios$MIN_IOS"

ODIN_ROOT=$(odin root)
CC="xcrun -sdk iphoneos clang -target $TARGET"
CFLAGS="-O2 -fPIC"

mkdir -p "$DEPS" "$OUT"

# --- native libraries --------------------------------------------------------------------------

if [ ! -f "$DEPS/libpffft.a" ]; then
    echo "Building pffft"
    $CC $CFLAGS -c "$ROOT/external/pffft/pffft.c" -o "$DEPS/pffft.o"
    ar rcs "$DEPS/libpffft.a" "$DEPS/pffft.o"
fi

if [ ! -f "$DEPS/libpa_ringbuffer.a" ]; then
    echo "Building pa_ringbuffer"
    $CC $CFLAGS -c "$ROOT/external/portaudio/src/common/pa_ringbuffer.c" -o "$DEPS/pa_ringbuffer.o"
    ar rcs "$DEPS/libpa_ringbuffer.a" "$DEPS/pa_ringbuffer.o"
fi

if [ ! -f "$DEPS/libminiaudio.a" ]; then
    echo "Building miniaudio"
    mkdir -p "$DEPS/miniaudio"
    # miniaudio has to be compiled as Objective-C on iOS for the AVAudioSession setup
    for src in "$ODIN_ROOT"/vendor/miniaudio/src/*.c; do
        $CC $CFLAGS -x objective-c -DMA_NO_RUNTIME_LINKING -c "$src" -o "$DEPS/miniaudio/$(basename "$src" .c).o"
    done
    ar rcs "$DEPS/libminiaudio.a" "$DEPS"/miniaudio/*.o
fi

if [ ! -f "$DEPS/libstb.a" ]; then
    echo "Building stb"
    mkdir -p "$DEPS/stb"
    for src in "$ODIN_ROOT"/vendor/stb/src/*.c; do
        $CC $CFLAGS -c "$src" -o "$DEPS/stb/$(basename "$src" .c).o"
    done
    ar rcs "$DEPS/libstb.a" "$DEPS"/stb/*.o
fi

if [ ! -d "$DEPS/SDL" ]; then
    # Match the desktop SDL, the Odin bindings are written against it
    SDL_VERSION=${SDL_VERSION:-$(brew list --versions sdl3 | awk '{print $2}')}
    git clone --depth 1 --branch "release-$SDL_VERSION" https://github.com/libsdl-org/SDL "$DEPS/SDL"
fi

if [ ! -f "$DEPS/sdl3/lib/libSDL3.a" ]; then
    echo "Building SDL"
    cmake -S "$DEPS/SDL" -B "$DEPS/SDL/build" \
        -DCMAKE_SYSTEM_NAME=iOS \
        -DCMAKE_OSX_SYSROOT=iphoneos \
        -DCMAKE_OSX_ARCHITECTURES=arm64 \
        -DCMAKE_OSX_DEPLOYMENT_TARGET=$MIN_IOS \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_INSTALL_PREFIX="$DEPS/sdl3" \
        -DSDL_SHARED=OFF \
        -DSDL_STATIC=ON \
        -DSDL_TEST_LIBRARY=OFF \
        -DSDL_EXAMPLES=OFF
    cmake --build "$DEPS/SDL/build" --config Release --parallel
    cmake --install "$DEPS/SDL/build" --config Release
fi

# --- app ---------------------------------------------------------------------------------------

echo "Compiling app"
odin build "$ROOT/app" \
    -build-mode:obj \
    -use-single-module \
    -target:darwin_arm64 \
    -subtarget:iphone \
    -minimum-os-version:$MIN_IOS \
    -define:RENDERER=sdl \
    -define:IOS=true \
    -o:speed \
    -out:"$OUT/app.o"

echo "Linking"
mkdir -p "$APP"
$CC -ObjC \
    "$OUT/app.o" \
    "$DEPS/libpffft.a" \
    "$DEPS/libpa_ringbuffer.a" \
    "$DEPS/libminiaudio.a" \
    "$DEPS/libstb.a" \
    "$DEPS/sdl3/lib/libSDL3.a" \
    -liconv \
    -framework Foundation \
    -framework UIKit \
    -framework CoreFoundation \
    -framework CoreGraphics \
    -framework QuartzCore \
    -framework Metal \
    -framework AVFoundation \
    -framework AudioToolbox \
    -framework CoreAudio \
    -framework CoreMedia \
    -framework CoreVideo \
    -framework CoreMotion \
    -framework CoreHaptics \
    -framework CoreBluetooth \
    -framework GameController \
    -framework OpenGLES \
    -framework UniformTypeIdentifiers \
    -o "$APP/StrobeTuner"

# --- signing -----------------------------------------------------------------------------------

if [ -z "${IOS_PROFILE:-}" ] || [ ! -f "$IOS_PROFILE" ]; then
    echo "Set IOS_PROFILE to the Ad Hoc provisioning profile (.mobileprovision)"
    exit 1
fi

# The entitlements and the bundle id come from the profile, its application-identifier is <team id>.<bundle id>
security cms -D -i "$IOS_PROFILE" > "$OUT/profile.plist"
/usr/libexec/PlistBuddy -x -c 'Print :Entitlements' "$OUT/profile.plist" > "$OUT/entitlements.plist"
APP_ID=$(/usr/libexec/PlistBuddy -c 'Print :Entitlements:application-identifier' "$OUT/profile.plist")
BUNDLE_ID=${APP_ID#*.}

cp "$ROOT/ios/Info.plist" "$APP/Info.plist"
# A wildcard profile (<team id>.*) signs any bundle id, keep the one in Info.plist
case "$BUNDLE_ID" in
    *'*'*) BUNDLE_ID=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP/Info.plist") ;;
    *) plutil -replace CFBundleIdentifier -string "$BUNDLE_ID" "$APP/Info.plist" ;;
esac

# The icon, actool makes the sizes from the 1024px one and lists them in a partial Info.plist
xcrun actool "$ROOT/ios/Assets.xcassets" --compile "$APP" --platform iphoneos --minimum-deployment-target $MIN_IOS \
    --app-icon AppIcon --output-partial-info-plist "$OUT/icon-info.plist" > /dev/null
/usr/libexec/PlistBuddy -c "Merge $OUT/icon-info.plist" "$APP/Info.plist"
plutil -replace CFBundleSupportedPlatforms -json '["iPhoneOS"]' "$APP/Info.plist"
cp "$IOS_PROFILE" "$APP/embedded.mobileprovision"

# Only development profiles allow attaching a debugger
if [ "$(/usr/libexec/PlistBuddy -c 'Print :Entitlements:get-task-allow' "$OUT/profile.plist" 2>/dev/null)" = true ]; then
    DEFAULT_IDENTITY="Apple Development"
else
    DEFAULT_IDENTITY="Apple Distribution"
fi
codesign --force --sign "${IOS_SIGN_IDENTITY:-$DEFAULT_IDENTITY}" --entitlements "$OUT/entitlements.plist" "$APP"

# An .ipa is a zip with the app inside a Payload folder
ditto -c -k --keepParent "$OUT/Payload" "$IPA"
echo "Built $IPA ($BUNDLE_ID)"

if [ -n "${IOS_DEVICE:-}" ]; then
    xcrun devicectl device install app --device "$IOS_DEVICE" "$APP"
    xcrun devicectl device process launch --device "$IOS_DEVICE" "$BUNDLE_ID"
fi
