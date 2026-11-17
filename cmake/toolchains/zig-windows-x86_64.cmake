# Cross-compile toolchain: Windows x86-64, MinGW/GNU (via zig cc/c++).
set(CMAKE_SYSTEM_NAME Windows)
set(CMAKE_SYSTEM_PROCESSOR x86_64)

set(CMAKE_C_COMPILER "zig;cc;-target;x86_64-windows-gnu")
set(CMAKE_CXX_COMPILER "zig;c++;-target;x86_64-windows-gnu")

set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_PACKAGE ONLY)

# Static archives are created with `zig ar rcs` ('s' writes the symbol
# index). On non-Windows targets CMake honors these (platform modules
# only set them when undefined). For Windows targets the platform
# modules set the archive rules unconditionally, so the Windows targets
# use the CMAKE_AR/CMAKE_RANLIB wrappers from cmake/host-ar.cmake.
set(CMAKE_C_ARCHIVE_CREATE "zig ar rcs <TARGET> <OBJECTS>")
set(CMAKE_CXX_ARCHIVE_CREATE "zig ar rcs <TARGET> <OBJECTS>")
set(CMAKE_C_ARCHIVE_APPEND "zig ar r <TARGET> <OBJECTS>")
set(CMAKE_CXX_ARCHIVE_APPEND "zig ar r <TARGET> <OBJECTS>")
set(CMAKE_C_ARCHIVE_FINISH "")
set(CMAKE_CXX_ARCHIVE_FINISH "")

# Host ar/ranlib wrappers for the Windows platform modules (see
# cmake/host-ar.cmake).
include("${CMAKE_CURRENT_LIST_DIR}/../host-ar.cmake")
