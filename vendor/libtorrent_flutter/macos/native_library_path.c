#include <dlfcn.h>

const char* lt_library_path(void) {
  Dl_info info;
  return dladdr((const void*)&lt_library_path, &info) ? info.dli_fname : 0;
}
