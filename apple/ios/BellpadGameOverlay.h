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

#ifdef __cplusplus
}
#endif
