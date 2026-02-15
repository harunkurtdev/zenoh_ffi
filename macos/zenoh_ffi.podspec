#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint zenoh_ffi.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'zenoh_ffi'
  s.version          = '0.0.1'
  s.summary          = 'A new Flutter FFI plugin project.'
  s.description      = <<-DESC
A new Flutter FFI plugin project.
                       DESC
  s.homepage         = 'http://example.com'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Your Company' => 'email@example.com' }
  
  # This will ensure the source files in Classes/ are included in the native
  # builds of apps using this FFI plugin. Podspec does not support relative
  # paths, so Classes contains a forwarder C file that relatively imports
  # `../src/*` so that the C sources can be shared among all target platforms.
  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'
  s.dependency 'FlutterMacOS'
  
  s.platform = :osx, '10.11'
  s.swift_version = '5.0'
  
  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'HEADER_SEARCH_PATHS' => '$(inherited) "${PODS_TARGET_SRCROOT}/../src/build_macos/_deps/zenohc-src/include"',
    'LIBRARY_SEARCH_PATHS' => '$(inherited) "${PODS_TARGET_SRCROOT}/../src/build_macos"',
    'OTHER_LDFLAGS' => '$(inherited) -lzenohc -lzenoh_ffi'
  }
  
  # CMake build via prepare_command
  # NOTE: All build output is redirected to a log file to avoid CocoaPods
  # Encoding::CompatibilityError from cargo's non-UTF8 progress output.
  s.prepare_command = <<-CMD
    set -e
    export LANG=en_US.UTF-8
    export LC_ALL=en_US.UTF-8
    export PATH="$HOME/.cargo/bin:/usr/local/bin:/opt/homebrew/bin:$PATH"

    if ! command -v cargo > /dev/null 2>&1; then
      echo "Error: cargo not found!"
      echo "Please install Rust: curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh"
      exit 1
    fi

    PLUGIN_ROOT="$(cd .. && pwd)"
    SRC_DIR="${PLUGIN_ROOT}/src"

    if [ ! -d "${SRC_DIR}" ]; then
      echo "Error: ${SRC_DIR} not found!"
      exit 1
    fi

    cd "${SRC_DIR}"
    mkdir -p build_macos
    cd build_macos

    BUILD_LOG="${SRC_DIR}/build_macos/build.log"

    # Skip rebuild if libraries already exist
    if [ -f "libzenoh_ffi.dylib" ] && [ -f "libzenohc.dylib" ]; then
      echo "macOS libraries already built, skipping rebuild."
      exit 0
    fi

    # Always start with a clean CMake cache to avoid stale platform configs
    rm -rf CMakeCache.txt CMakeFiles

    echo "Building zenoh-c for macOS (this may take several minutes)..."
    echo "Build log: ${BUILD_LOG}"

    export SDKROOT=$(xcrun --sdk macosx --show-sdk-path)
    export CC=/usr/bin/clang
    export CXX=/usr/bin/clang++
    export AR=/usr/bin/ar

    # Run cmake configure + build, redirect ALL output to log file
    # This avoids CocoaPods encoding errors from cargo's binary progress output
    (
      cmake .. -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_OSX_ARCHITECTURES="$(uname -m)" \
        -DCMAKE_OSX_SYSROOT=$SDKROOT \
        -Wno-dev \
      && cmake --build . --config Release
    ) > "$BUILD_LOG" 2>&1

    BUILD_EXIT=$?
    if [ $BUILD_EXIT -ne 0 ]; then
      echo "Build FAILED. Last 30 lines of log:"
      tail -30 "$BUILD_LOG" | LC_ALL=C tr -cd '[:print:][:space:]'
      exit 1
    fi

    # Verify outputs
    if [ -f "libzenoh_ffi.dylib" ] && [ -f "libzenohc.dylib" ]; then
      echo "zenoh-c built successfully for macOS"
    else
      echo "Build completed but dylibs not found. Check ${BUILD_LOG}"
      exit 1
    fi
  CMD


  s.script_phases = [
      {
        :name => 'Build Zenoh-C via CMake',
        :script => %q{
          set -e
          export LANG=en_US.UTF-8
          export LC_ALL=en_US.UTF-8
          export PATH="$HOME/.cargo/bin:/usr/local/bin:/opt/homebrew/bin:$PATH"

          SRC_DIR="${PODS_TARGET_SRCROOT}/../src"
          BUILD_DIR="${SRC_DIR}/build_macos"

          # Skip if already built
          if [ -f "${BUILD_DIR}/libzenoh_ffi.dylib" ] && [ -f "${BUILD_DIR}/libzenohc.dylib" ]; then
            echo "Libraries already built, skipping..."
            exit 0
          fi

          if ! command -v cargo > /dev/null 2>&1; then
            echo "Error: cargo not found! Please install Rust."
            exit 1
          fi

          mkdir -p "$BUILD_DIR"
          cd "$BUILD_DIR"
          rm -rf CMakeCache.txt CMakeFiles

          export SDKROOT=$(xcrun --sdk macosx --show-sdk-path)
          export CC=/usr/bin/clang
          export CXX=/usr/bin/clang++
          export AR=/usr/bin/ar

          BUILD_LOG="${BUILD_DIR}/build.log"
          (
            cmake .. -DCMAKE_BUILD_TYPE=Release -DCMAKE_OSX_ARCHITECTURES="$(uname -m)" -DCMAKE_OSX_SYSROOT=$SDKROOT -Wno-dev \
            && cmake --build . --config Release
          ) > "$BUILD_LOG" 2>&1
          BUILD_EXIT=$?
          if [ $BUILD_EXIT -ne 0 ]; then
            echo "Build FAILED. Last 30 lines:"
            tail -30 "$BUILD_LOG" | LC_ALL=C tr -cd '[:print:][:space:]'
            exit 1
          fi
          echo "zenoh-c built successfully"
        },
        :execution_position => :before_compile
      },
      {
        :name => 'Copy Zenoh Libraries to App Bundle',
        :script => %q{
          set -e
          FRAMEWORKS_DIR="${TARGET_BUILD_DIR}/${FRAMEWORKS_FOLDER_PATH}"
          mkdir -p "${FRAMEWORKS_DIR}"
          cp -R "${PODS_TARGET_SRCROOT}/../src/build_macos/libzenoh_ffi.dylib" "${FRAMEWORKS_DIR}/"
          cp -R "${PODS_TARGET_SRCROOT}/../src/build_macos/libzenohc.dylib" "${FRAMEWORKS_DIR}/"
          codesign -f -s "${EXPANDED_CODE_SIGN_IDENTITY}" "${FRAMEWORKS_DIR}/libzenoh_ffi.dylib" || true
          codesign -f -s "${EXPANDED_CODE_SIGN_IDENTITY}" "${FRAMEWORKS_DIR}/libzenohc.dylib" || true
        },
        :execution_position => :after_compile
      }
    ]



  # Preserve paths - CMake build artifacts
  s.preserve_paths = [
    '../src/build_macos/**/*',
    '../src/build_macos/_deps/zenohc-src/include/**/*'
  ]

  # Vendored libraries
  s.vendored_libraries = [
    '../src/build_macos/libzenoh_ffi.dylib',
    '../src/build_macos/libzenohc.dylib'
  ]
  
  s.public_header_files = [
    'Classes/**/*.h'
  ]
end