# cmake/host-ar.cmake — select the committed zig-ar/zig-ranlib wrapper for
# the build HOST (the machine running the compiler), based on OS and arch.
#
# The Windows platform modules (Windows-Clang/-GNU) set the archive rules
# unconditionally to "<CMAKE_AR> qc <TARGET> <LINK_FLAGS> <OBJECTS>" and
# "<CMAKE_RANLIB> <TARGET>" with a response file (@objects.rsp), so the
# cross toolchains must give CMAKE_AR/CMAKE_RANLIB a runnable program on
# the host. The wrappers rewrite the call into `zig ar rcs` / `zig ar s`
# and expand the response file themselves.

if(CMAKE_HOST_WIN32)
    set(_host_os windows)
    set(_suffix .exe)
    if(CMAKE_HOST_SYSTEM_PROCESSOR MATCHES "^[Aa][Rr][Mm]64|^aarch64")
        set(_host_arch arm64)
    else()
        set(_host_arch x86_64)
    endif()
elseif(CMAKE_HOST_APPLE)
    set(_host_os macos)
    set(_suffix "")
    if(CMAKE_HOST_SYSTEM_PROCESSOR MATCHES "arm64|aarch64")
        set(_host_arch arm64)
    else()
        set(_host_arch x86_64)
    endif()
elseif(CMAKE_HOST_UNIX)
    set(_host_os linux)
    set(_suffix "")
    if(CMAKE_HOST_SYSTEM_PROCESSOR MATCHES "arm64|aarch64")
        set(_host_arch arm64)
    else()
        set(_host_arch x86_64)
    endif()
else()
    message(FATAL_ERROR "host-ar: unsupported build host (${CMAKE_HOST_SYSTEM_NAME})")
endif()

get_filename_component(_host_ar_dir "${CMAKE_CURRENT_LIST_FILE}" PATH)
set(CMAKE_AR "${_host_ar_dir}/wrappers/zig-ar-${_host_os}-${_host_arch}${_suffix}")
set(CMAKE_RANLIB "${_host_ar_dir}/wrappers/zig-ranlib-${_host_os}-${_host_arch}${_suffix}")

if(NOT EXISTS "${CMAKE_AR}")
    message(FATAL_ERROR "host-ar: wrapper not found: ${CMAKE_AR}")
endif()

unset(_host_os)
unset(_host_arch)
unset(_suffix)
unset(_host_ar_dir)
