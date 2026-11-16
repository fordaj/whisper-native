# Cross-compile toolchain: Windows ARM64 (aarch64), MinGW/GNU (via zig cc/c++).
set(CMAKE_SYSTEM_NAME Windows)
set(CMAKE_SYSTEM_PROCESSOR aarch64)

set(CMAKE_C_COMPILER "zig;cc;-target;aarch64-windows-gnu")
set(CMAKE_CXX_COMPILER "zig;c++;-target;aarch64-windows-gnu")

set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_PACKAGE ONLY)

# Use Zig's binutils so archives match the cross target (host ranlib
# cannot read ELF/COFF members).
set(CMAKE_AR "${CMAKE_CURRENT_LIST_DIR}/../wrappers/zig-ar")
set(CMAKE_RANLIB "${CMAKE_CURRENT_LIST_DIR}/../wrappers/zig-ranlib")
