#include <memory>
#include <type_traits>

#include "ggml-backend-dl.h"

#ifdef _WIN32

#include <cstdio>

dl_handle * dl_load_library(const fs::path & path) {
    return LoadLibraryW(path.c_str());
}

void * dl_get_sym(dl_handle * handle, const char * name) {
    return reinterpret_cast<void *>(GetProcAddress(reinterpret_cast<HMODULE>(handle), name));
}

const char * dl_error() {
    static thread_local char err_buf[512] = { 0 };
    const DWORD err = GetLastError();
    if (err == 0) {
        return "unknown";
    }

    const DWORD flags = FORMAT_MESSAGE_FROM_SYSTEM | FORMAT_MESSAGE_IGNORE_INSERTS;
    const DWORD written = FormatMessageA(
        flags,
        nullptr,
        err,
        0,
        err_buf,
        static_cast<DWORD>(sizeof(err_buf)),
        nullptr
    );
    if (written == 0) {
        std::snprintf(err_buf, sizeof(err_buf), "win32 error code %lu", static_cast<unsigned long>(err));
    }
    return err_buf;
}

#else

dl_handle * dl_load_library(const fs::path & path) {
    return dlopen(path.c_str(), RTLD_NOW | RTLD_LOCAL);
}

void * dl_get_sym(dl_handle * handle, const char * name) {
    return dlsym(handle, name);
}

const char * dl_error() {
    const char * err = dlerror();
    return err != nullptr ? err : "unknown";
}

#endif
