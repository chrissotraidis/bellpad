#pragma once

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
