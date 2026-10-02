cmake_minimum_required(VERSION 3.24)
if(POLICY CMP0167)
  cmake_policy(SET CMP0167 NEW)
endif()
project(libtorrent_flutter LANGUAGES C CXX)

include(FetchContent)
set(BUILD_SHARED_LIBS OFF CACHE BOOL "" FORCE)
set(OPENSSL_USE_STATIC_LIBS TRUE)
set(CMAKE_FIND_PACKAGE_PREFER_CONFIG TRUE)
FetchContent_Declare(libtorrent
  URL https://github.com/arvidn/libtorrent/releases/download/v2.1.2/libtorrent-rasterbar-2.1.2.tar.gz
  URL_HASH SHA256=3362546d9cd71b9e49ee6cac7d3f1f914ce9cdb217c86b63d5b22cbed0334dbc
  DOWNLOAD_EXTRACT_TIMESTAMP TRUE
)
FetchContent_MakeAvailable(libtorrent)

add_library(libtorrent_flutter SHARED
  ../src/torrent_bridge.cpp
  native_library_path.c
)
target_compile_features(libtorrent_flutter PRIVATE cxx_std_17)
target_link_libraries(libtorrent_flutter PRIVATE torrent-rasterbar)
target_link_options(libtorrent_flutter PRIVATE "-Wl,-exported_symbol,_lt_*" "-Wl,-dead_strip")
set_target_properties(libtorrent_flutter PROPERTIES
  BUILD_WITH_INSTALL_NAME_DIR TRUE
  INSTALL_NAME_DIR "@rpath"
)
