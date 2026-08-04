#include <dolphin/gx/GXStruct.h>

#include <cstddef>
#include <cstdio>

template <typename T>
void report(const char* name) {
    std::printf("%s %zu %zu\n", name, sizeof(T), alignof(T));
}

int main() {
    report<GXRenderModeObj>("GXRenderModeObj");
    report<GXColor>("GXColor");
    report<GXTexObj>("GXTexObj");
    report<GXTlutObj>("GXTlutObj");
    report<GXLightObj>("GXLightObj");
    report<GXColorS10>("GXColorS10");
    report<GXFogAdjTable>("GXFogAdjTable");
    report<GXVtxDescList>("GXVtxDescList");
    report<GXVtxAttrFmtList>("GXVtxAttrFmtList");
    return 0;
}
