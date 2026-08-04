#pragma once

#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

/* Attaches Bellpad's UIKit controls above the SDL/Aurora game view. Safe to
 * call from SDL's game thread; UIKit work is marshalled to the main thread. */
void bellpad_install_game_overlay(void);

/* Returns a validated retained ISO/GCM path. When no valid retained image is
 * present, this holds core boot while UIKit presents a native Files import
 * screen; SDL's main-thread entry keeps the UIKit run loop pumping. */
int bellpad_prepare_game_data_path(const char* application_support_path,
                                   char* output_path,
                                   size_t output_capacity);

enum {
    BELLPAD_NATIVE_TEXT_NONE = 0,
    BELLPAD_NATIVE_TEXT_BACKSPACE = 1,
    BELLPAD_NATIVE_TEXT_ENTER = 2,
};

/* The game thread publishes editor state and drains UIKit keyboard events.
 * Text is UTF-8; commands use BELLPAD_NATIVE_TEXT_* above. */
void bellpad_set_native_text_active(int active);
int bellpad_poll_native_text_event(char* utf8,
                                   size_t utf8_capacity,
                                   int* command);

/* Returns the user's internal render-resolution scale. Zero selects the
 * device's native drawable resolution; one and two select 1x and 2x EFB. */
float bellpad_get_framebuffer_scale(void);

#ifdef __cplusplus
}
#endif
