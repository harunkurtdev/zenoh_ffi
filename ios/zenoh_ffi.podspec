#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint zenoh_ffi.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'zenoh_ffi'
  s.version          = '0.1.0'
  s.summary          = 'Dart FFI binding for Zenoh protocol.'
  s.description      = <<-DESC
A Dart/Flutter FFI binding for Zenoh protocol enabling high-performance pub/sub,
query/reply, and distributed computing.
                       DESC
  s.homepage         = 'https://github.com/harunkurtdev/zenoh_ffi'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Harun Kurt' => 'harunkurtdev@example.com' }

  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'
  s.dependency 'Flutter'
  s.platform = :ios, '13.0'
  s.swift_version = '5.0'
  s.static_framework = true

  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386',
    'HEADER_SEARCH_PATHS' => '$(inherited) "${PODS_TARGET_SRCROOT}/../src/build/_deps/zenohc-src/include"',
  }

  # Use -force_load to ensure ALL C symbols from static archives are included.
  # Plain -l flags would let the linker dead-strip unreferenced symbols, but
  # Dart FFI uses dlsym at runtime so all symbols must be present.
  s.user_target_xcconfig = {
    'OTHER_LDFLAGS[sdk=iphoneos*]' => '$(inherited) -force_load "${PODS_ROOT}/../.symlinks/plugins/zenoh_ffi/ios/../src/build/device_libs/libzenohc.a" -force_load "${PODS_ROOT}/../.symlinks/plugins/zenoh_ffi/ios/../src/build/device_libs/libzenoh_ffi.a"',
    'OTHER_LDFLAGS[sdk=iphonesimulator*]' => '$(inherited) -force_load "${PODS_ROOT}/../.symlinks/plugins/zenoh_ffi/ios/../src/build/sim_libs/libzenohc.a" -force_load "${PODS_ROOT}/../.symlinks/plugins/zenoh_ffi/ios/../src/build/sim_libs/libzenoh_ffi.a"',
  }

  s.preserve_paths = [
    '../src/build/**/*',
    '../src/build/_deps/zenohc-src/include/**/*'
  ]

  s.public_header_files = [
    'Classes/**/*.h'
  ]

  # Build zenoh-c via cargo during pod install (runs OUTSIDE Xcode environment).
  # Builds for BOTH device (aarch64-apple-ios) and simulator (aarch64-apple-ios-sim).
  # Libraries are placed in separate dirs (device_libs/ sim_libs/) since both are
  # arm64 and cannot be combined with lipo.
  s.prepare_command = <<-CMD
    set -e
    echo "================================================"
    echo "Building zenoh-c for iOS (device + simulator)..."
    echo "================================================"

    export PATH="$HOME/.cargo/bin:/usr/local/bin:/opt/homebrew/bin:$PATH"
    export CC=/usr/bin/clang
    export CXX=/usr/bin/clang++
    export AR=/usr/bin/ar

    if ! command -v cargo &> /dev/null; then
      echo "Error: cargo not found!"
      echo "Please install Rust: curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh"
      exit 1
    fi

    echo "Found cargo: $(which cargo)"
    echo "Rust version: $(rustc --version)"

    # Install both Rust targets
    rustup target add aarch64-apple-ios 2>/dev/null || true
    rustup target add aarch64-apple-ios-sim 2>/dev/null || true

    PLUGIN_ROOT="$(cd .. && pwd)"
    SRC_DIR="${PLUGIN_ROOT}/src"

    if [ ! -d "${SRC_DIR}" ]; then
      echo "Error: ${SRC_DIR} not found!"
      exit 1
    fi

    cd "${SRC_DIR}"

    # Skip rebuild if libraries already exist
    if [ -f "build/device_libs/libzenohc.a" ] && [ -f "build/sim_libs/libzenohc.a" ] && \
       [ -f "build/device_libs/libzenoh_ffi.a" ] && [ -f "build/sim_libs/libzenoh_ffi.a" ]; then
      echo "================================================"
      echo "Libraries already built, skipping rebuild."
      echo "Delete src/build to force rebuild."
      echo "================================================"
      ls -lh build/device_libs/*.a build/sim_libs/*.a
      exit 0
    fi

    # Force remove previous build (cargo target dirs may have restricted perms)
    chmod -R u+w build 2>/dev/null || true
    rm -rf build
    mkdir -p build
    cd build

    DEVICE_SDK=$(xcrun --sdk iphoneos --show-sdk-path)
    SIM_SDK=$(xcrun --sdk iphonesimulator --show-sdk-path)

    # ================================================================
    # Step 1: Use CMake configure ONLY to fetch zenoh-c via FetchContent
    # ================================================================
    echo "Configuring CMake (FetchContent only)..."

    cmake .. \
      -DCMAKE_BUILD_TYPE=Release \
      -DCMAKE_SYSTEM_NAME=iOS \
      -DCMAKE_OSX_ARCHITECTURES=arm64 \
      -DCMAKE_OSX_SYSROOT=${DEVICE_SDK} \
      -DCMAKE_OSX_DEPLOYMENT_TARGET=13.0 \
      -DIOS=TRUE

    ZENOHC_SRC_DIR="$(pwd)/_deps/zenohc-src"
    if [ ! -d "$ZENOHC_SRC_DIR" ]; then
      echo "Error: zenohc-src not found after cmake configure!"
      exit 1
    fi
    echo "zenoh-c source: $ZENOHC_SRC_DIR"

    # ================================================================
    # Step 2: Fetch cargo deps & patch zenoh-c 1.6.2 for iOS
    # ================================================================
    echo "================================================"
    echo "Fetching cargo deps and patching for iOS..."
    echo "================================================"

    cd "$ZENOHC_SRC_DIR"
    cargo fetch --target aarch64-apple-ios 2>&1 || true
    cd - > /dev/null

    PATCHED=0
    for MOD_RS in $(find "$HOME/.cargo/git/checkouts" -path "*/zenoh-util/src/net/mod.rs" 2>/dev/null); do
      if grep -q 'target_os = "macos", target_os = "windows")' "$MOD_RS" && ! grep -q 'target_os = "ios"' "$MOD_RS"; then
        echo "Patching: $MOD_RS"
        sed -i '' 's/target_os = "macos", target_os = "windows"/target_os = "macos", target_os = "windows", target_os = "ios"/g' "$MOD_RS"
        PATCHED=$((PATCHED + 1))
      fi
    done
    echo "Patched $PATCHED file(s) for iOS support"

    # ================================================================
    # Step 3: Build zenohc for device (aarch64-apple-ios)
    # ================================================================
    echo "================================================"
    echo "Building zenohc for DEVICE (aarch64-apple-ios)..."
    echo "================================================"
    echo "Free disk space: $(df -h / | tail -1 | awk '{print $4}')"

    cd "$ZENOHC_SRC_DIR"
    SDKROOT="$DEVICE_SDK" IPHONEOS_DEPLOYMENT_TARGET=13.0 \
      cargo build --release --target aarch64-apple-ios --lib
    cd - > /dev/null

    mkdir -p device_libs
    DEVICE_ZENOHC="$ZENOHC_SRC_DIR/target/aarch64-apple-ios/release/libzenohc.a"
    if [ -f "$DEVICE_ZENOHC" ]; then
      cp "$DEVICE_ZENOHC" device_libs/libzenohc.a
      echo "Device libzenohc.a ready"
    else
      echo "ERROR: Device libzenohc.a not found!"
      find "$ZENOHC_SRC_DIR/target" -name "libzenohc.a" 2>/dev/null || true
      exit 1
    fi

    # Build zenoh_ffi.c for device
    echo "Building zenoh_ffi.c for device..."
    /usr/bin/clang -c \
      -target arm64-apple-ios13.0 \
      -isysroot "$DEVICE_SDK" \
      -I"$ZENOHC_SRC_DIR/include" \
      -I"${SRC_DIR}" \
      -DDART_SHARED_LIB \
      -O2 \
      -o device_libs/zenoh_ffi.o \
      "${SRC_DIR}/zenoh_ffi.c"
    /usr/bin/ar rcs device_libs/libzenoh_ffi.a device_libs/zenoh_ffi.o
    echo "Device libzenoh_ffi.a ready"

    # Clean device build intermediates to free disk space
    echo "Cleaning device build intermediates..."
    rm -rf "$ZENOHC_SRC_DIR/target/aarch64-apple-ios"
    rm -rf "$ZENOHC_SRC_DIR/target/release"
    echo "Free disk space: $(df -h / | tail -1 | awk '{print $4}')"

    # ================================================================
    # Step 4: Build zenohc for simulator (aarch64-apple-ios-sim)
    # ================================================================
    echo "================================================"
    echo "Building zenohc for SIMULATOR (aarch64-apple-ios-sim)..."
    echo "================================================"

    cd "$ZENOHC_SRC_DIR"
    SDKROOT="$SIM_SDK" IPHONEOS_DEPLOYMENT_TARGET=13.0 \
      cargo build --release --target aarch64-apple-ios-sim --lib
    cd - > /dev/null

    mkdir -p sim_libs
    SIM_ZENOHC="$ZENOHC_SRC_DIR/target/aarch64-apple-ios-sim/release/libzenohc.a"
    if [ -f "$SIM_ZENOHC" ]; then
      cp "$SIM_ZENOHC" sim_libs/libzenohc.a
      echo "Simulator libzenohc.a ready"
    else
      echo "ERROR: Simulator libzenohc.a not found!"
      find "$ZENOHC_SRC_DIR/target" -name "libzenohc.a" 2>/dev/null || true
      exit 1
    fi

    # Build zenoh_ffi.c for simulator
    echo "Building zenoh_ffi.c for simulator..."
    /usr/bin/clang -c \
      -target arm64-apple-ios13.0-simulator \
      -isysroot "$SIM_SDK" \
      -I"$ZENOHC_SRC_DIR/include" \
      -I"${SRC_DIR}" \
      -DDART_SHARED_LIB \
      -O2 \
      -o sim_libs/zenoh_ffi.o \
      "${SRC_DIR}/zenoh_ffi.c"
    /usr/bin/ar rcs sim_libs/libzenoh_ffi.a sim_libs/zenoh_ffi.o
    echo "Simulator libzenoh_ffi.a ready"

    # Clean all build intermediates
    echo "Cleaning build intermediates..."
    rm -rf "$ZENOHC_SRC_DIR/target"

    echo "================================================"
    echo "Build artifacts:"
    echo "Device:"
    ls -lh device_libs/*.a 2>/dev/null || echo "  No device .a files"
    echo "Simulator:"
    ls -lh sim_libs/*.a 2>/dev/null || echo "  No simulator .a files"
    echo "================================================"
  CMD
end
