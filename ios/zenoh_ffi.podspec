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
  s.source_files = 'Classes/**/*'
  s.dependency 'Flutter'
  s.platform = :ios, '13.0'

  # Flutter.framework does not contain a i386 slice.
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
  s.swift_version = '5.0'

  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'HEADER_SEARCH_PATHS' => '$(inherited) "${PODS_TARGET_SRCROOT}/../src/build/_deps/zenohc-src/include"',
    'LIBRARY_SEARCH_PATHS' => '$(inherited) "${PODS_TARGET_SRCROOT}/../src/build"',
    'OTHER_LDFLAGS' => '$(inherited) -lzenohc -lzenoh_ffi'
  }
  
  # CMake build için prepare_command
    s.prepare_command = <<-CMD
    set -e
    echo "================================================"
    echo "Building zenoh-c via CMake for iOS..."
    echo "Current directory: $(pwd)"
    echo "================================================"
    
    export PATH="$HOME/.cargo/bin:/usr/local/bin:/opt/homebrew/bin:$PATH"
    
    if ! command -v cargo &> /dev/null; then
      echo "❌ Error: cargo not found!"
      echo "Please install Rust: curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh"
      exit 1
    fi
    
    echo "✓ Found cargo: $(which cargo)"
    echo "✓ Rust version: $(rustc --version)"
    # Determine architecture and SDK first to know which Rust target to install
  ARCH="arm64"
  SDK="iphoneos"
  RUST_TARGET="aarch64-apple-ios"
  
  if [ "${CONFIGURATION}" = "Debug" ] || [ "${SDKROOT}" = "$(xcrun --sdk iphonesimulator --show-sdk-path)" ]; then
    SDK="iphonesimulator"
    if [ "$(uname -m)" = "x86_64" ]; then
      ARCH="x86_64"
      RUST_TARGET="x86_64-apple-ios"
    else
      ARCH="arm64"
      RUST_TARGET="aarch64-apple-ios-sim"
    fi
  fi
  
  # Install required Rust targets and toolchains
  echo "Installing Rust target: ${RUST_TARGET}..."
  if [ "${RUST_TARGET}" = "aarch64-apple-ios-sim" ]; then
    rustup toolchain install nightly 2>/dev/null || true
    rustup +nightly target list --installed | grep ${RUST_TARGET} || rustup +nightly target add ${RUST_TARGET} 2>/dev/null
  else
    rustup toolchain install stable 2>/dev/null || true
    rustup default stable
    rustup target list --installed | grep ${RUST_TARGET} || rustup target add ${RUST_TARGET} 2>/dev/null
  fi
  echo "✓ Rust target installed"
  
  PLUGIN_ROOT="$(cd .. && pwd)"
  SRC_DIR="${PLUGIN_ROOT}/src"
  
  echo "Plugin root: ${PLUGIN_ROOT}"
  echo "Source dir: ${SRC_DIR}"
  
  if [ ! -d "${SRC_DIR}" ]; then
    echo "❌ Error: ${SRC_DIR} not found!"
    echo "Available directories in ${PLUGIN_ROOT}:"
    ls -la "${PLUGIN_ROOT}"
    exit 1
  fi
  
  cd "${SRC_DIR}"
  echo "Working in: $(pwd)"
  
  # Clean any previous builds
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

    # Build
    echo "Running CMake build..."
    cmake --build . --config Release
    
    echo "================================================"
    echo "✓ zenoh-c built successfully!"
    echo "Build artifacts:"
    ls -lh *.a 2>/dev/null || echo "No .a files found"
    echo "================================================"
  CMD

  # App bundle'a kopyalama script phase --- IGNORE ---
  # TODO: fix codesign issues on iphoneos Ventura and later
  # s.script_phases = [
  #     {
  #       :name => 'Copy Zenoh Libraries to App Bundle',
  #               :script => 'set -e
  #         FRAMEWORKS_DIR="${TARGET_BUILD_DIR}/${FRAMEWORKS_FOLDER_PATH}"
  #         mkdir -p "${FRAMEWORKS_DIR}"
  #         cp -R "${PODS_TARGET_SRCROOT}/../src/build/libzenoh_ffi.dylib" "${FRAMEWORKS_DIR}/"
  #         cp -R "${PODS_TARGET_SRCROOT}/../src/build/libzenohc.dylib" "${FRAMEWORKS_DIR}/"
  #         # cp -R "${PODS_TARGET_SRCROOT}/../src/build/zenoh_ffi.framework" "${FRAMEWORKS_DIR}/"
  #         codesign -f -s "${EXPANDED_CODE_SIGN_IDENTITY}" "${FRAMEWORKS_DIR}/libzenoh_ffi.dylib" || true
  #         codesign -f -s "${EXPANDED_CODE_SIGN_IDENTITY}" "${FRAMEWORKS_DIR}/libzenohc.dylib" || true
  #         # codesign -f -s "${EXPANDED_CODE_SIGN_IDENTITY}" "${FRAMEWORKS_DIR}/zenoh_ffi.framework" || true
  #         ',
  #       :execution_position => :after_compile
  #     }
  #   ]


  # Preserve paths - CMake build ürünlerini koru
  s.preserve_paths = [
    '../src/build/**/*',
    '../src/build/_deps/zenohc-src/include/**/*',
    '../src/_deps/**/*'
  ]
  
  # Vendored libraries
  s.vendored_libraries = [
  '../src/build/libzenoh_ffi.a',  
  '../src/build/libzenohc.a'      
]

  s.vendored_frameworks = '../src/build/zenoh_ffi.framework'
  
  s.public_header_files = [
    'Classes/**/*.h'
  ]
end
