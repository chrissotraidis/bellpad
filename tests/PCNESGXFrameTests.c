#include "pc_nes_gx_frame.h"

#include <assert.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

static uint16_t source[PC_NES_FRAME_WIDTH * PC_NES_FRAME_HEIGHT];
static uint8_t texture[PC_NES_GX_TEXTURE_BYTES];

static void expect_pixel(size_t byte_offset, uint16_t value) {
    assert(texture[byte_offset] == (uint8_t)(value >> 8));
    assert(texture[byte_offset + 1] == (uint8_t)value);
}

int main(void) {
    memset(source, 0, sizeof(source));
    memset(texture, 0xcd, sizeof(texture));

    assert(!pc_nes_convert_frame_to_gx(NULL, sizeof(source) / sizeof(source[0]),
                                       texture, sizeof(texture)));
    assert(!pc_nes_convert_frame_to_gx(source,
                                       sizeof(source) / sizeof(source[0]) - 1,
                                       texture, sizeof(texture)));
    assert(!pc_nes_convert_frame_to_gx(source, sizeof(source) / sizeof(source[0]),
                                       NULL, sizeof(texture)));
    assert(!pc_nes_convert_frame_to_gx(source, sizeof(source) / sizeof(source[0]),
                                       texture, sizeof(texture) - 1));

    /* Rows above the visible crop contain a value that must not appear. */
    for (int y = 0; y < PC_NES_VISIBLE_TOP; ++y) {
        for (int x = 0; x < PC_NES_FRAME_WIDTH; ++x) {
            source[y * PC_NES_FRAME_WIDTH + x] = 0xffff;
        }
    }

    const size_t first_row = (size_t)PC_NES_VISIBLE_TOP * PC_NES_FRAME_WIDTH;
    source[first_row + 0] = 0x001f; /* fixNES red */
    source[first_row + 1] = 0x07e0; /* green */
    source[first_row + 2] = 0xf800; /* fixNES blue */
    source[first_row + 3] = 0xffff; /* white */
    source[first_row + 4] = 0x1234;
    source[first_row + PC_NES_FRAME_WIDTH] = 0x0011;
    source[first_row + PC_NES_FRAME_WIDTH * 4] = 0x5aa5;
    source[(PC_NES_VISIBLE_TOP + PC_NES_VISIBLE_HEIGHT - 1) * PC_NES_FRAME_WIDTH +
           PC_NES_FRAME_WIDTH - 1] = 0x4321;

    assert(pc_nes_convert_frame_to_gx(source, sizeof(source) / sizeof(source[0]),
                                      texture, sizeof(texture)));

    /* Pixels are RGB-field-swapped, big-endian, and ordered inside 4x4 tiles. */
    expect_pixel(0, 0xf800);
    expect_pixel(2, 0x07e0);
    expect_pixel(4, 0x001f);
    expect_pixel(6, 0xffff);
    expect_pixel(8, (uint16_t)(((0x0011 & 0x001f) << 11) |
                               (0x0011 & 0x07e0) |
                               ((0x0011 & 0xf800) >> 11)));

    /* The next horizontal tile begins after one 32-byte 4x4 tile. */
    expect_pixel(32, (uint16_t)(((0x1234 & 0x001f) << 11) |
                                (0x1234 & 0x07e0) |
                                ((0x1234 & 0xf800) >> 11)));

    /* The next vertical tile row begins after 64 horizontal tiles. */
    expect_pixel(64 * 32, (uint16_t)(((0x5aa5 & 0x001f) << 11) |
                                     (0x5aa5 & 0x07e0) |
                                     ((0x5aa5 & 0xf800) >> 11)));

    expect_pixel(sizeof(texture) - 2,
                 (uint16_t)(((0x4321 & 0x001f) << 11) |
                            (0x4321 & 0x07e0) |
                            ((0x4321 & 0xf800) >> 11)));

    puts("PC NES GX frame conversion tests passed");
    return 0;
}
