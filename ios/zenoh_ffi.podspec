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

  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386',
    'HEADER_SEARCH_PATHS' => '$(inherited) "${PODS_TARGET_SRCROOT}/../src/build/_deps/zenohc-src/include"',
    'LIBRARY_SEARCH_PATHS' => '$(inherited) "${PODS_TARGET_SRCROOT}/../src/build"',
    'OTHER_LDFLAGS' => '$(inherited) -lzenohc -lzenoh_ffi'
  }

  # Build zenoh-c via CMake during pod install (runs OUTSIDE Xcode environment)
  s.prepare_command = <<-CMD
    set -e
    echo "================================================"
    echo "Building zenoh-c via CMake for iOS..."
    echo "================================================"

    export PATH="$HOME/.cargo/bin:/usr/local/bin:/opt/homebrew/bin:$PATH"

    if ! command -v cargo &> /dev/null; then
      echo "Error: cargo not found!"
      echo "Please install Rust: curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh"
      exit 1
    fi

    echo "Found cargo: $(which cargo)"
    echo "Rust version: $(rustc --version)"

    # Determine target
    ARCH="arm64"
    SDK="iphoneos"
    RUST_TARGET="aarch64-apple-ios"

    echo "Installing Rust target: ${RUST_TARGET}..."
    rustup target add ${RUST_TARGET} 2>/dev/null || true
    # Also add simulator target
    rustup target add aarch64-apple-ios-sim 2>/dev/null || true

    PLUGIN_ROOT="$(cd .. && pwd)"
    SRC_DIR="${PLUGIN_ROOT}/src"

    if [ ! -d "${SRC_DIR}" ]; then
      echo "Error: ${SRC_DIR} not found!"
      exit 1
    fi

    cd "${SRC_DIR}"
    rm -rf build
    mkdir -p build
    cd build

    export SDKROOT=$(xcrun --sdk ${SDK} --show-sdk-path)
    echo "Building for SDK: ${SDK}, Arch: ${ARCH}, Rust target: ${RUST_TARGET}"

    # Configure via CMake (this will FetchContent zenoh-c)
    cmake .. \
      -DCMAKE_BUILD_TYPE=Release \
      -DCMAKE_SYSTEM_NAME=iOS \
      -DCMAKE_OSX_ARCHITECTURES=${ARCH} \
      -DCMAKE_OSX_SYSROOT=${SDKROOT} \
      -DCMAKE_OSX_DEPLOYMENT_TARGET=13.0 \
      -DIOS=TRUE

    # ================================================================
    # PATCH: zenoh-c 1.6.2 iOS support
    # zenoh-util has cfg gates for set_bind_to_device_{tcp,udp}_socket
    # that cover linux/android/macos/windows but NOT ios.
    # We fetch deps first, then patch the source in cargo's git cache.
    # ================================================================
    echo "================================================"
    echo "Patching zenoh-util for iOS support..."
    echo "================================================"

    ZENOHC_SRC_DIR=$(find _deps -name "zenohc-src" -type d 2>/dev/null | head -1)
    if [ -n "$ZENOHC_SRC_DIR" ]; then
      cd "$ZENOHC_SRC_DIR"
      # Fetch all cargo dependencies so source is available
      cargo fetch --target ${RUST_TARGET} 2>&1 || true
      cd - > /dev/null
    fi

    # Patch all zenoh-util/src/net/mod.rs files in cargo's git checkout cache
    PATCHED=0
    for MOD_RS in $(find "$HOME/.cargo/git/checkouts" -path "*/zenoh-util/src/net/mod.rs" 2>/dev/null); do
      if grep -q 'target_os = "macos", target_os = "windows")' "$MOD_RS" && ! grep -q 'target_os = "ios"' "$MOD_RS"; then
        echo "Patching: $MOD_RS"
        sed -i '' 's/target_os = "macos", target_os = "windows"/target_os = "macos", target_os = "windows", target_os = "ios"/g' "$MOD_RS"
        PATCHED=$((PATCHED + 1))
      fi
    done
    echo "Patched $PATCHED file(s) for iOS support"

    # Now build (the patched source will be used)
    echo "================================================"
    echo "Building with CMake..."
    echo "================================================"
    cmake --build . --config Release

    # Copy libzenohc.a to build root
    ZENOHC_LIB=$(find _deps/zenohc-src/target -name "libzenohc.a" -path "*/${RUST_TARGET}/release/*" 2>/dev/null | head -1)
    if [ -n "$ZENOHC_LIB" ]; then
      cp "$ZENOHC_LIB" "$(pwd)/libzenohc.a"
      echo "Copied libzenohc.a to build root"
    else
      echo "WARNING: libzenohc.a not found for ${RUST_TARGET}"
      find _deps/zenohc-src/target -name "libzenohc.a" 2>/dev/null || true
    fi

    # Also copy libzenoh_ffi.a if it's not already in build root
    if [ -f "libzenoh_ffi.a" ]; then
      echo "libzenoh_ffi.a already in build root"
    else
      FFI_LIB=$(find . -name "libzenoh_ffi.a" -not -path "./libzenoh_ffi.a" 2>/dev/null | head -1)
      if [ -n "$FFI_LIB" ]; then
        cp "$FFI_LIB" "$(pwd)/libzenoh_ffi.a"
        echo "Copied libzenoh_ffi.a to build root"
      fi
    fi

    echo "================================================"
    echo "Build artifacts:"
    ls -lh *.a 2>/dev/null || echo "No .a files found"
    echo "================================================"
  CMD

  s.preserve_paths = [
    '../src/build/**/*',
    '../src/build/_deps/zenohc-src/include/**/*'
  ]

  s.vendored_libraries = [
    '../src/build/libzenoh_ffi.a',
    '../src/build/libzenohc.a'
  ]

  s.public_header_files = [
    'Classes/**/*.h'
  ]
end
