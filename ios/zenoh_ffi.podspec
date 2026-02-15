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
  s.source_files     = 'Classes/**/*', '../src/zenoh_ffi.c', '../src/zenoh_ffi.h'
  s.dependency 'Flutter'
  s.platform = :ios, '13.0'
  s.swift_version = '5.0'

  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386 x86_64',
    'VALID_ARCHS' => 'arm64',
    'HEADER_SEARCH_PATHS' => '$(inherited) "${PODS_TARGET_SRCROOT}/../src/include"',
    'OTHER_LDFLAGS' => '$(inherited) -framework Foundation -framework Security -framework SystemConfiguration -lresolv'
  }

  s.user_target_xcconfig = {
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386 x86_64'
  }

  # Static library olarak build et
  s.static_framework = true

  s.public_header_files = [
    '../src/zenoh_ffi.h'
  ]

  # Script phase ile zenoh-c'yi build et
  s.script_phases = [
    {
      :name => 'Build Zenoh-C',
      :script => %q{
        set -ex
        export LC_ALL=en_US.UTF-8
        export LANG=en_US.UTF-8
        export PATH="$HOME/.cargo/bin:/usr/local/bin:/opt/homebrew/bin:$PATH"

        SRC_DIR="${PODS_TARGET_SRCROOT}/../src"
        BUILD_DIR="${SRC_DIR}/build"

        # Skip if already built for this target
        RUST_TARGET_FILE="${BUILD_DIR}/.rust_target"

        # Determine target
        if [[ "$PLATFORM_NAME" == *"simulator"* ]]; then
          if [[ "$ARCHS" == *"arm64"* ]]; then
            RUST_TARGET="aarch64-apple-ios-sim"
          else
            RUST_TARGET="x86_64-apple-ios"
          fi
        else
          RUST_TARGET="aarch64-apple-ios"
        fi

        echo "Building for RUST_TARGET: $RUST_TARGET"
        echo "PLATFORM_NAME: $PLATFORM_NAME"
        echo "ARCHS: $ARCHS"
        echo "SDKROOT: $SDKROOT"

        # Check if already built for same target
        if [ -f "${BUILD_DIR}/libzenoh_ffi.a" ] && [ -f "$RUST_TARGET_FILE" ]; then
          PREV_TARGET=$(cat "$RUST_TARGET_FILE")
          if [ "$PREV_TARGET" = "$RUST_TARGET" ]; then
            echo "Libraries already built for $RUST_TARGET, skipping..."
            exit 0
          fi
        fi

        # Clean previous build
        rm -rf "$BUILD_DIR"
        mkdir -p "$BUILD_DIR"

        # Install target
        rustup target add $RUST_TARGET || true

        cd "$BUILD_DIR"

        echo "Running CMake configure..."
        cmake .. \
          -DCMAKE_BUILD_TYPE=Release \
          -DCMAKE_SYSTEM_NAME=iOS \
          -DCMAKE_OSX_ARCHITECTURES="$ARCHS" \
          -DCMAKE_OSX_SYSROOT="$SDKROOT" \
          -DCMAKE_OSX_DEPLOYMENT_TARGET="${IPHONEOS_DEPLOYMENT_TARGET:-13.0}" \
          -DIOS=TRUE

        echo "Running CMake build..."
        cmake --build . --config Release

        # Save target info
        echo "$RUST_TARGET" > "$RUST_TARGET_FILE"

        echo "Build completed successfully"
        ls -la *.a 2>/dev/null || echo "No .a files in build dir"
      },
      :execution_position => :before_compile,
      :output_files => ['${PODS_TARGET_SRCROOT}/../src/build/libzenoh_ffi.a']
    }
  ]

  # Preserve paths
  s.preserve_paths = [
    '../src/**/*'
  ]
end
