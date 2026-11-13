#pragma once

#include <cstddef>
#include <cstdint>

enum BellpadButton : std::uint16_t {
    BellpadButtonDPadLeft = 1u << 0,
    BellpadButtonDPadRight = 1u << 1,
    BellpadButtonDPadDown = 1u << 2,
    BellpadButtonDPadUp = 1u << 3,
    BellpadButtonZ = 1u << 4,
    BellpadButtonR = 1u << 5,
    BellpadButtonL = 1u << 6,
    BellpadButtonA = 1u << 8,
    BellpadButtonB = 1u << 9,
    BellpadButtonX = 1u << 10,
    BellpadButtonY = 1u << 11,
    BellpadButtonStart = 1u << 12,
};

struct BellpadPadState {
    std::uint16_t buttons = 0;
    std::int8_t stickX = 0;
    std::int8_t stickY = 0;
    std::int8_t cStickX = 0;
    std::int8_t cStickY = 0;
    std::uint8_t triggerL = 0;
    std::uint8_t triggerR = 0;
};

enum class BellpadInputSource : std::uint8_t {
    Touch,
    Controller,
};

void BellpadSetInputState(BellpadInputSource source, const BellpadPadState& state);
void BellpadClearInputState(BellpadInputSource source);
BellpadPadState BellpadGetMergedInputState();

extern "C" int bellpad_copy_normalized_pad_state(
    std::uint16_t* buttons,
    std::int8_t* stickX,
    std::int8_t* stickY,
    std::int8_t* cStickX,
    std::int8_t* cStickY,
    std::uint8_t* triggerL,
    std::uint8_t* triggerR);

// Touch drives port 0. Aurora assigns each physical gamepad a player index, so
// only a gamepad on player 0 stands in for the touch controls; a gamepad on
// another port, or one with no port, never hides them.
inline bool BellpadTouchPlayerHasController(const int* playerIndexes, std::size_t count) {
    for (std::size_t i = 0; i < count; ++i) {
        if (playerIndexes[i] == 0) return true;
    }
    return false;
}

// Layout editing always shows the controls so it stays escapable. Otherwise a
// manual hide, or auto-hide while the touch player has a controller, hides
// them. "Show Touch Controls" clears both, so it wins with a controller still
// connected.
inline bool BellpadTouchControlsHidden(bool editingLayout, bool manuallyHidden,
                                       bool autoHide, bool touchPlayerHasController) {
    return !editingLayout && (manuallyHidden || (autoHide && touchPlayerHasController));
}
