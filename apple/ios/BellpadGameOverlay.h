#pragma once

#ifdef __cplusplus
extern "C" {
#endif

/* Attaches Bellpad's UIKit controls above the SDL/Aurora game view. Safe to
 * call from SDL's game thread; UIKit work is marshalled to the main thread. */
void bellpad_install_game_overlay(void);

#ifdef __cplusplus
}
#endif
