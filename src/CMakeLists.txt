cmake_minimum_required(VERSION 3.14)
project(zenoh_dart_library VERSION 0.0.1 LANGUAGES C)
include(FetchContent)

# Zenoh-C Download & Setup
FetchContent_Declare(
    zenohc
    GIT_REPOSITORY https://github.com/eclipse-zenoh/zenoh-c.git
    GIT_TAG 1.6.2
    GIT_SHALLOW TRUE
    GIT_PROGRESS TRUE
)


# --- Platform Detection (FIXED) ---
set(IS_IOS FALSE)
set(IS_ANDROID FALSE)
set(IS_MACOS FALSE)


if(ANDROID)
    set(IS_ANDROID TRUE)
    message(STATUS "Platform: Android")
# iOS detection MUST come before macOS check
elseif(CMAKE_SYSTEM_NAME STREQUAL "iOS" OR IOS OR CMAKE_OSX_SYSROOT MATCHES "iphone")
    set(IS_IOS TRUE)
    message(STATUS "Platform: iOS")
elseif(CMAKE_SYSTEM_NAME STREQUAL "Darwin")
    set(IS_MACOS TRUE)
    message(STATUS "Platform: macOS")
endif()


if(IS_IOS)
    FetchContent_MakeAvailable(zenohc)
else()
    FetchContent_GetProperties(zenohc)
endif()


# set(NATIVE_OUTPUT_DIR ${CMAKE_CURRENT_SOURCE_DIR}/include)
# file(MAKE_DIRECTORY ${NATIVE_OUTPUT_DIR})


if(NOT zenohc_POPULATED)
    message(STATUS "Downloading zenoh-c...")
    FetchContent_Populate(zenohc)
    message(STATUS "zenoh-c downloaded to: ${zenohc_SOURCE_DIR}")
    # if (IS_IOS)
    #     # Patch Cargo.toml to force staticlib for iOS compatibility
    #     file(READ ${zenohc_SOURCE_DIR}/Cargo.toml CARGO_TOML_CONTENT)
    #     string(REPLACE "crate-type = [\"cdylib\"]" "crate-type = [\"staticlib\"]" MODIFIED_CONTENT "${CARGO_TOML_CONTENT}")
    #     string(REPLACE "crate-type = [\"dylib\"]" "crate-type = [\"staticlib\"]" MODIFIED_CONTENT "${MODIFIED_CONTENT}")
    #     string(REPLACE "crate-type = [\"cdylib\", \"rlib\"]" "crate-type = [\"staticlib\"]" MODIFIED_CONTENT "${MODIFIED_CONTENT}")
    #     file(WRITE ${zenohc_SOURCE_DIR}/Cargo.toml "${MODIFIED_CONTENT}")
    #     message(STATUS "Patched zenoh-c Cargo.toml to use staticlib")
    # endif()
endif()

# --- ANDROID Configuration ---
if(IS_ANDROID)
    message(STATUS "Building for Android ABI: ${ANDROID_ABI}")
    
    if(${ANDROID_ABI} STREQUAL "arm64-v8a")
        set(ZENOHC_TARGET "aarch64-linux-android")
        set(ANDROID_TOOLCHAIN_PREFIX "aarch64-linux-android")
    elseif(${ANDROID_ABI} STREQUAL "armeabi-v7a")
        set(ZENOHC_TARGET "armv7-linux-androideabi")
        set(ANDROID_TOOLCHAIN_PREFIX "armv7a-linux-androideabi")
    elseif(${ANDROID_ABI} STREQUAL "x86_64")
        set(ZENOHC_TARGET "x86_64-linux-android")
        set(ANDROID_TOOLCHAIN_PREFIX "x86_64-linux-android")
    elseif(${ANDROID_ABI} STREQUAL "x86")
        set(ZENOHC_TARGET "i686-linux-android")
        set(ANDROID_TOOLCHAIN_PREFIX "i686-linux-android")
    else()
        message(FATAL_ERROR "❌ Unsupported ANDROID_ABI: ${ANDROID_ABI}")
    endif()
    
    set(ZENOHC_BUILD_DIR "${zenohc_SOURCE_DIR}")
    set(ZENOHC_LIB "${ZENOHC_BUILD_DIR}/target/${ZENOHC_TARGET}/release/libzenohc.so")
    set(CARGO_CONFIG_DIR "${ZENOHC_BUILD_DIR}/.cargo")
    set(CARGO_CONFIG_FILE "${CARGO_CONFIG_DIR}/config.toml")
    
    message(STATUS "Zenoh-C source directory: ${zenohc_SOURCE_DIR}")
    message(STATUS "Zenoh-C library path: ${ZENOHC_LIB}")
    message(STATUS "Android toolchain prefix: ${ANDROID_TOOLCHAIN_PREFIX}")
    
    # Create .cargo/config.toml for cross-compilation
    file(MAKE_DIRECTORY ${CARGO_CONFIG_DIR})
    file(WRITE ${CARGO_CONFIG_FILE}
"[target.${ZENOHC_TARGET}]
linker = \"${ANDROID_NDK}/toolchains/llvm/prebuilt/linux-x86_64/bin/${ANDROID_TOOLCHAIN_PREFIX}21-clang\"
ar = \"${ANDROID_NDK}/toolchains/llvm/prebuilt/linux-x86_64/bin/llvm-ar\"
")
    
    message(STATUS "Created Cargo config at: ${CARGO_CONFIG_FILE}")
    
    # Convert target name to uppercase and replace dashes with underscores for env var names
    string(TOUPPER ${ZENOHC_TARGET} ZENOHC_TARGET_UPPER)
    string(REPLACE "-" "_" ZENOHC_TARGET_UPPER_UNDERSCORE ${ZENOHC_TARGET_UPPER})
    
    # Also need the version with underscores replacing hyphens (for cc crate)
    string(REPLACE "-" "_" ZENOHC_TARGET_UNDERSCORE ${ZENOHC_TARGET})
    
    # --- Rust (Zenoh-C) build command for Android ---
    add_custom_command(
        OUTPUT ${ZENOHC_LIB}
        COMMAND ${CMAKE_COMMAND} -E env
            CC_${ZENOHC_TARGET}=${ANDROID_NDK}/toolchains/llvm/prebuilt/linux-x86_64/bin/${ANDROID_TOOLCHAIN_PREFIX}21-clang
            CXX_${ZENOHC_TARGET}=${ANDROID_NDK}/toolchains/llvm/prebuilt/linux-x86_64/bin/${ANDROID_TOOLCHAIN_PREFIX}21-clang++
            AR_${ZENOHC_TARGET}=${ANDROID_NDK}/toolchains/llvm/prebuilt/linux-x86_64/bin/llvm-ar
            CC_${ZENOHC_TARGET_UNDERSCORE}=${ANDROID_NDK}/toolchains/llvm/prebuilt/linux-x86_64/bin/${ANDROID_TOOLCHAIN_PREFIX}21-clang
            CXX_${ZENOHC_TARGET_UNDERSCORE}=${ANDROID_NDK}/toolchains/llvm/prebuilt/linux-x86_64/bin/${ANDROID_TOOLCHAIN_PREFIX}21-clang++
            AR_${ZENOHC_TARGET_UNDERSCORE}=${ANDROID_NDK}/toolchains/llvm/prebuilt/linux-x86_64/bin/llvm-ar
            CARGO_TARGET_${ZENOHC_TARGET_UPPER_UNDERSCORE}_LINKER=${ANDROID_NDK}/toolchains/llvm/prebuilt/linux-x86_64/bin/${ANDROID_TOOLCHAIN_PREFIX}21-clang
            cargo build --release --target ${ZENOHC_TARGET}
        WORKING_DIRECTORY ${zenohc_SOURCE_DIR}
        COMMENT "Building zenoh-c for Android target: ${ZENOHC_TARGET}"
        VERBATIM
    )
    
    add_custom_target(build_zenohc_android ALL DEPENDS ${ZENOHC_LIB})
endif()

# --- iOS Configuration (FIXED) ---
if(IS_IOS)
    message(STATUS "Building for iOS")
    message(STATUS "CMAKE_OSX_ARCHITECTURES: ${CMAKE_OSX_ARCHITECTURES}")
    message(STATUS "CMAKE_OSX_SYSROOT: ${CMAKE_OSX_SYSROOT}")
    
    # Determine iOS target based on SDK
    if(CMAKE_OSX_SYSROOT MATCHES "iphonesimulator")
        # iOS Simulator
        if(CMAKE_OSX_ARCHITECTURES MATCHES "arm64")
            set(RUST_TARGET "aarch64-apple-ios-sim")
            set(CARGO_TOOLCHAIN "+nightly")
            set(BUILD_STD "-Z build-std")
        elseif(CMAKE_OSX_ARCHITECTURES MATCHES "x86_64")
            set(RUST_TARGET "x86_64-apple-ios")
            set(CARGO_TOOLCHAIN "")
            set(BUILD_STD "")
        else()
            set(RUST_TARGET "aarch64-apple-ios-sim")
            set(CARGO_TOOLCHAIN "+nightly")
            set(BUILD_STD "-Z build-std")
        endif()
        message(STATUS "Detected iOS Simulator build: ${RUST_TARGET}")
    else()
        # iOS Device
        set(RUST_TARGET "aarch64-apple-ios")
        set(CARGO_TOOLCHAIN "")
        set(BUILD_STD "")
        message(STATUS "Detected iOS Device build")
    endif()
    
    set(ZENOHC_BUILD_DIR "${zenohc_SOURCE_DIR}")
    set(ZENOHC_LIB "${ZENOHC_BUILD_DIR}/target/${RUST_TARGET}/release/libzenohc.a")
    
    message(STATUS "iOS Rust target: ${RUST_TARGET}")
    message(STATUS "Zenoh-C library path: ${ZENOHC_LIB}")
    
    # Ensure nightly toolchain is installed for simulator builds
    if(CARGO_TOOLCHAIN STREQUAL "+nightly")
        execute_process(
            COMMAND rustup toolchain list
            OUTPUT_VARIABLE TOOLCHAIN_LIST
            OUTPUT_STRIP_TRAILING_WHITESPACE
            ERROR_QUIET
        )
        if(NOT TOOLCHAIN_LIST MATCHES "nightly")
            message(STATUS "Installing Rust nightly toolchain for iOS simulator...")
            execute_process(
                COMMAND rustup toolchain install nightly
                RESULT_VARIABLE RUSTUP_RESULT
                OUTPUT_QUIET
                ERROR_QUIET
            )
            if(NOT RUSTUP_RESULT EQUAL 0)
                message(WARNING "Failed to install Rust nightly toolchain automatically. Please run: rustup toolchain install nightly")
            endif()
        endif()
        
        # Add iOS simulator target
        message(STATUS "Ensuring Rust target ${RUST_TARGET} is installed...")
        execute_process(
            COMMAND rustup ${CARGO_TOOLCHAIN} target add ${RUST_TARGET}
            RESULT_VARIABLE RUSTUP_RESULT
            OUTPUT_QUIET
            ERROR_QUIET
        )
        if(NOT RUSTUP_RESULT EQUAL 0)
            message(WARNING "Could not verify target ${RUST_TARGET}. Please run: rustup +nightly target add ${RUST_TARGET}")
        endif()
    else()
        # Add iOS device target
        message(STATUS "Ensuring Rust target ${RUST_TARGET} is installed...")
        execute_process(
            COMMAND rustup target add ${RUST_TARGET}
            RESULT_VARIABLE RUSTUP_RESULT
            OUTPUT_QUIET
            ERROR_QUIET
        )
        if(NOT RUSTUP_RESULT EQUAL 0)
            message(WARNING "Could not verify target ${RUST_TARGET}. Please run: rustup target add ${RUST_TARGET}")
        endif()
    endif()
    
    # Clean any existing macOS builds to prevent wrong architecture linking
    add_custom_command(
        OUTPUT ${ZENOHC_LIB}
        # Remove any macOS dylib that might interfere
        COMMAND ${CMAKE_COMMAND} -E remove -f ${ZENOHC_BUILD_DIR}/target/aarch64-apple-darwin/release/libzenohc.dylib
        COMMAND ${CMAKE_COMMAND} -E remove -f ${ZENOHC_BUILD_DIR}/target/x86_64-apple-darwin/release/libzenohc.dylib
        # Build for iOS target with explicit Rust environment
        COMMAND ${CMAKE_COMMAND} -E env 
            RUSTUP_HOME=$ENV{HOME}/.rustup
            CARGO_HOME=$ENV{HOME}/.cargo
            cargo ${CARGO_TOOLCHAIN} build --release --target ${RUST_TARGET} --lib ${BUILD_STD}
        # Verify the output is a static library
        COMMAND ${CMAKE_COMMAND} -E echo "Verifying iOS build..."
        COMMAND test -f ${ZENOHC_LIB} || (echo "ERROR: Static library not found at ${ZENOHC_LIB}" && exit 1)
        COMMAND file ${ZENOHC_LIB}
        WORKING_DIRECTORY ${zenohc_SOURCE_DIR}
        COMMENT "Building zenoh-c static library for iOS target: ${RUST_TARGET}"
        VERBATIM
    )
    
    add_custom_target(build_zenohc_ios ALL DEPENDS ${ZENOHC_LIB})
endif()

# --- Zenoh Dart library ---
if (IS_IOS)
    add_library(zenoh_dart STATIC
        "zenoh_dart.c"
    )
else()
    add_library(zenoh_dart SHARED
        "zenoh_dart.c"
    )
endif()

set_target_properties(zenoh_dart PROPERTIES
    PUBLIC_HEADER zenoh_dart.h
    OUTPUT_NAME "zenoh_dart"
)

# Platform-specific properties
if(IS_ANDROID)
    set_target_properties(zenoh_dart PROPERTIES
        BUILD_RPATH "\$ORIGIN"
        INSTALL_RPATH "\$ORIGIN"
        LINK_FLAGS "-Wl,-rpath,'\$ORIGIN'"
    )
elseif(IS_IOS)
    # iOS doesn't support dynamic libraries in the same way
    # Set minimal properties for iOS framework
    set_target_properties(zenoh_dart PROPERTIES
        FRAMEWORK FALSE
        XCODE_ATTRIBUTE_CODE_SIGN_IDENTITY ""
        XCODE_ATTRIBUTE_CODE_SIGNING_REQUIRED "NO"
        XCODE_ATTRIBUTE_ENABLE_BITCODE "NO"
    )
elseif(IS_MACOS)
    set_target_properties(zenoh_dart PROPERTIES
        BUILD_WITH_INSTALL_RPATH TRUE
        INSTALL_NAME_DIR "@rpath"
        BUILD_RPATH "@loader_path"
        INSTALL_RPATH "@loader_path"
    )
elseif(UNIX)
    set_target_properties(zenoh_dart PROPERTIES
        BUILD_RPATH "\$ORIGIN"
        INSTALL_RPATH "\$ORIGIN"
    )
endif()

# Include directories
if(IS_ANDROID)
    target_include_directories(zenoh_dart
        PRIVATE
        ${zenohc_SOURCE_DIR}/include
        ${zenohc_BINARY_DIR}/include
        ${CMAKE_CURRENT_SOURCE_DIR}
    )
elseif(IS_IOS)
    target_include_directories(zenoh_dart
        PUBLIC
        ${zenohc_SOURCE_DIR}/include
        PRIVATE
        ${CMAKE_CURRENT_SOURCE_DIR}
    )
else()
    target_include_directories(zenoh_dart
        PUBLIC
        ${zenohc_SOURCE_DIR}/include
        PRIVATE
        ${CMAKE_CURRENT_SOURCE_DIR}
    )
endif()

target_compile_definitions(zenoh_dart PUBLIC DART_SHARED_LIB)

# --- Link libraries ---
if(IS_ANDROID)
    find_library(log-lib log)
    add_dependencies(zenoh_dart build_zenohc_android)
    
    # Import zenohc as an imported library
    add_library(zenohc SHARED IMPORTED)
    set_target_properties(zenohc PROPERTIES
        IMPORTED_LOCATION ${ZENOHC_LIB}
        IMPORTED_NO_SONAME TRUE
    )
    
    # Link zenoh_dart with zenohc and log
    target_link_libraries(zenoh_dart PRIVATE ${log-lib} zenohc)
    
    # Set linker flags to use relative RPATH
    target_link_options(zenoh_dart PRIVATE
        "-Wl,-rpath,'$ORIGIN'"
        "-Wl,--enable-new-dtags"
    )
    
    # Copy libzenohc.so to the output directory so it's included in the APK
    add_custom_command(TARGET zenoh_dart POST_BUILD
        COMMAND ${CMAKE_COMMAND} -E copy_if_different
            ${ZENOHC_LIB}
            $<TARGET_FILE_DIR:zenoh_dart>/libzenohc.so
        COMMAND ${CMAKE_COMMAND} -E echo "Copied libzenohc.so to $<TARGET_FILE_DIR:zenoh_dart>/"
        COMMENT "Copying libzenohc.so to output directory"
    )
elseif(IS_IOS)
    # iOS specific linking
    add_dependencies(zenoh_dart build_zenohc_ios)
    
    # Import zenohc as a static library for iOS
    add_library(zenohc STATIC IMPORTED)
    set_target_properties(zenohc PROPERTIES
        IMPORTED_LOCATION ${ZENOHC_LIB}
        INTERFACE_INCLUDE_DIRECTORIES ${zenohc_SOURCE_DIR}/include
    )
    
    # Link with static library and system frameworks
    target_link_libraries(zenoh_dart PRIVATE 
        zenohc
        "-framework Foundation"
        "-framework Security"
        "-framework SystemConfiguration"
        "-lresolv"
        "-lc++"
    )
    
    # Force static linking of zenohc
    target_link_options(zenoh_dart PRIVATE
        "-force_load" "${ZENOHC_LIB}"
    )
else()
    # For non-Android/iOS platforms (Linux, macOS, Windows)
    message(STATUS "Building for ${CMAKE_SYSTEM_NAME}")
    message(STATUS "Processor: ${CMAKE_SYSTEM_PROCESSOR}")
    
    # Determine the Rust target triple for the host system
    if(CMAKE_SYSTEM_NAME STREQUAL "Linux")
        if(CMAKE_SYSTEM_PROCESSOR MATCHES "x86_64|amd64|AMD64")
            set(RUST_TARGET "x86_64-unknown-linux-gnu")
            set(LIB_EXTENSION "so")
        elseif(CMAKE_SYSTEM_PROCESSOR MATCHES "aarch64|arm64|ARM64")
            set(RUST_TARGET "aarch64-unknown-linux-gnu")
            set(LIB_EXTENSION "so")
        elseif(CMAKE_SYSTEM_PROCESSOR MATCHES "armv7|armv7l")
            set(RUST_TARGET "armv7-unknown-linux-gnueabihf")
            set(LIB_EXTENSION "so")
        elseif(CMAKE_SYSTEM_PROCESSOR MATCHES "i686|i386|x86")
            set(RUST_TARGET "i686-unknown-linux-gnu")
            set(LIB_EXTENSION "so")
        elseif(CMAKE_SYSTEM_PROCESSOR MATCHES "riscv64")
            set(RUST_TARGET "riscv64gc-unknown-linux-gnu")
            set(LIB_EXTENSION "so")
        else()
            message(WARNING "Unknown Linux processor: ${CMAKE_SYSTEM_PROCESSOR}, defaulting to x86_64")
            set(RUST_TARGET "x86_64-unknown-linux-gnu")
            set(LIB_EXTENSION "so")
        endif()
    elseif(CMAKE_SYSTEM_NAME STREQUAL "Darwin")
        if(CMAKE_SYSTEM_PROCESSOR MATCHES "x86_64")
            set(RUST_TARGET "x86_64-apple-darwin")
        elseif(CMAKE_SYSTEM_PROCESSOR MATCHES "arm64")
            set(RUST_TARGET "aarch64-apple-darwin")
        else()
            message(WARNING "Unknown macOS processor: ${CMAKE_SYSTEM_PROCESSOR}, defaulting to x86_64")
            set(RUST_TARGET "x86_64-apple-darwin")
        endif()
        set(LIB_EXTENSION "dylib")
    elseif(CMAKE_SYSTEM_NAME STREQUAL "Windows")
        if(CMAKE_SYSTEM_PROCESSOR MATCHES "AMD64|x86_64")
            set(RUST_TARGET "x86_64-pc-windows-msvc")
        elseif(CMAKE_SYSTEM_PROCESSOR MATCHES "ARM64|aarch64")
            set(RUST_TARGET "aarch64-pc-windows-msvc")
        elseif(CMAKE_SYSTEM_PROCESSOR MATCHES "x86|i686")
            set(RUST_TARGET "i686-pc-windows-msvc")
        else()
            message(WARNING "Unknown Windows processor: ${CMAKE_SYSTEM_PROCESSOR}, defaulting to x86_64")
            set(RUST_TARGET "x86_64-pc-windows-msvc")
        endif()
        set(LIB_EXTENSION "dll")
    elseif(CMAKE_SYSTEM_NAME STREQUAL "FreeBSD")
        if(CMAKE_SYSTEM_PROCESSOR MATCHES "x86_64|amd64")
            set(RUST_TARGET "x86_64-unknown-freebsd")
        elseif(CMAKE_SYSTEM_PROCESSOR MATCHES "i686|i386")
            set(RUST_TARGET "i686-unknown-freebsd")
        endif()
        set(LIB_EXTENSION "so")
    elseif(CMAKE_SYSTEM_NAME STREQUAL "NetBSD")
        if(CMAKE_SYSTEM_PROCESSOR MATCHES "x86_64|amd64")
            set(RUST_TARGET "x86_64-unknown-netbsd")
        endif()
        set(LIB_EXTENSION "so")
    else()
        message(FATAL_ERROR "Unsupported platform: ${CMAKE_SYSTEM_NAME}")
    endif()
    
    set(ZENOHC_BUILD_DIR "${zenohc_SOURCE_DIR}")
    
    if(WIN32)
        set(ZENOHC_LIB "${ZENOHC_BUILD_DIR}/target/${RUST_TARGET}/release/zenohc.${LIB_EXTENSION}")
        set(ZENOHC_IMPLIB "${ZENOHC_BUILD_DIR}/target/${RUST_TARGET}/release/zenohc.dll.lib")
    else()
        set(ZENOHC_LIB "${ZENOHC_BUILD_DIR}/target/${RUST_TARGET}/release/libzenohc.${LIB_EXTENSION}")
    endif()

    message(STATUS "Rust target: ${RUST_TARGET}")
    message(STATUS "Library extension: ${LIB_EXTENSION}")
    message(STATUS "Zenoh-C library path: ${ZENOHC_LIB}")

    # Build zenohc using Cargo
    add_custom_command(
        OUTPUT ${ZENOHC_LIB}
        COMMAND cargo build --release --target ${RUST_TARGET}
        WORKING_DIRECTORY ${zenohc_SOURCE_DIR}
        COMMENT "Building zenoh-c for ${RUST_TARGET}"
    )
    
    add_custom_target(build_zenohc ALL DEPENDS ${ZENOHC_LIB})
    
    # Import zenohc as an imported library
    add_library(zenohc SHARED IMPORTED)
    set_target_properties(zenohc PROPERTIES
        IMPORTED_LOCATION ${ZENOHC_LIB}
        INTERFACE_INCLUDE_DIRECTORIES ${zenohc_SOURCE_DIR}/include
    )
    
    if(WIN32 AND EXISTS ${ZENOHC_IMPLIB})
        set_target_properties(zenohc PROPERTIES
            IMPORTED_IMPLIB ${ZENOHC_IMPLIB}
        )
    endif()
    
    add_dependencies(zenoh_dart build_zenohc)
    target_link_libraries(zenoh_dart PRIVATE zenohc)
    
    # Platform-specific linking options
    if(IS_MACOS)
        target_link_options(zenoh_dart PRIVATE
            "-Wl,-rpath,@loader_path"
            "-Wl,-rpath,@loader_path/../Frameworks"
        )
    elseif(UNIX AND NOT APPLE)
        # Linux and BSD systems
        target_link_options(zenoh_dart PRIVATE
            "-Wl,-rpath,$ORIGIN"
        )
    endif()
    
    # Copy zenohc library to output directory
    if(IS_MACOS)
        add_custom_command(TARGET zenoh_dart POST_BUILD
            # Copy libzenohc.dylib to framework's Versions/A directory
            COMMAND ${CMAKE_COMMAND} -E copy_if_different
                ${ZENOHC_LIB}
                $<TARGET_FILE_DIR:zenoh_dart>/libzenohc.dylib
            # Configure libzenohc.dylib install name
            COMMAND install_name_tool -id "@rpath/libzenohc.dylib" 
                $<TARGET_FILE_DIR:zenoh_dart>/libzenohc.dylib
            # Update zenohc reference in zenoh_dart to use @rpath
            COMMAND install_name_tool -change 
                "${ZENOHC_LIB}"
                "@rpath/libzenohc.dylib"
                $<TARGET_FILE:zenoh_dart>
            # Verify the configuration
            COMMAND ${CMAKE_COMMAND} -E echo "✓ Framework binary install name:"
            COMMAND otool -D $<TARGET_FILE:zenoh_dart>
            COMMAND ${CMAKE_COMMAND} -E echo ""
            COMMAND ${CMAKE_COMMAND} -E echo "✓ Framework binary dependencies:"
            COMMAND otool -L $<TARGET_FILE:zenoh_dart>
            COMMENT "Configuring zenoh-c library for macOS framework"
        )
    else()
        add_custom_command(TARGET zenoh_dart POST_BUILD
            COMMAND ${CMAKE_COMMAND} -E copy_if_different
                ${ZENOHC_LIB}
                $<TARGET_FILE_DIR:zenoh_dart>/
            COMMENT "Copying zenoh-c library to output directory"
        )
    endif()
endif()

if(NOT IS_ANDROID)
    # Only hide symbols on non-Android platforms if needed
    # set_target_properties(zenoh_dart PROPERTIES
    #     C_VISIBILITY_PRESET hidden
    #     VISIBILITY_INLINES_HIDDEN YES
    # )
endif()

# --- Windows export symbol handling ---
if(WIN32)
    target_compile_definitions(zenoh_dart PRIVATE ZENOH_DART_EXPORTS)
endif()