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

    # For simulator on Apple Silicon
    if [ "$(uname -m)" = "arm64" ]; then
      # Build for both device and simulator-compatible target
      # Default to device; simulator build handled separately if needed
      RUST_TARGET="aarch64-apple-ios"
    fi

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

    cmake .. \
      -DCMAKE_BUILD_TYPE=Release \
      -DCMAKE_SYSTEM_NAME=iOS \
      -DCMAKE_OSX_ARCHITECTURES=${ARCH} \
      -DCMAKE_OSX_SYSROOT=${SDKROOT} \
      -DCMAKE_OSX_DEPLOYMENT_TARGET=13.0 \
      -DIOS=TRUE

    cmake --build . --config Release

    # Copy libzenohc.a to build root
    ZENOHC_LIB=$(find _deps/zenohc-src/target -name "libzenohc.a" -path "*/${RUST_TARGET}/release/*" 2>/dev/null | head -1)
    if [ -n "$ZENOHC_LIB" ]; then
      cp "$ZENOHC_LIB" "$(pwd)/libzenohc.a"
      echo "Copied libzenohc.a"
    else
      echo "WARNING: libzenohc.a not found for ${RUST_TARGET}"
      find _deps/zenohc-src/target -name "libzenohc.a" 2>/dev/null || true
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
