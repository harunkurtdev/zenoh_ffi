# The Flutter tooling requires that developers have CMake 3.10 or later
# installed. You should not increase this version, as doing so will cause
# the plugin to fail to compile for some customers of the plugin.
cmake_minimum_required(VERSION 3.10)

# Project-level configuration.
set(PROJECT_NAME "zenoh_ffi")
project(${PROJECT_NAME} LANGUAGES C CXX)

# Invoke the build for native code shared with the other target platforms.
add_subdirectory("${CMAKE_CURRENT_SOURCE_DIR}/../src" "${CMAKE_CURRENT_BINARY_DIR}/shared")

# List of absolute paths to libraries that should be bundled with the plugin.
# zenoh_ffi.so is our plugin, libzenohc.so is copied next to it by src/CMakeLists.txt post-build step.
set(zenoh_ffi_bundled_libraries
  $<TARGET_FILE:zenoh_ffi>
  "$<TARGET_FILE_DIR:zenoh_ffi>/libzenohc.so"
  PARENT_SCOPE
)
