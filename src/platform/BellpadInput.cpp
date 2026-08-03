#include "BellpadInput.h"

#include <algorithm>
#include <array>
#include <cmath>
#include <mutex>

namespace {

std::mutex gInputMutex;
std::array<BellpadPadState, 2> gInputStates{};

template <typename T>
T strongestAxis(T first, T second) {
    return std::abs(static_cast<int>(second)) > std::abs(static_cast<int>(first)) ? second : first;
}

std::size_t sourceIndex(BellpadInputSource source) {
    return source == BellpadInputSource::Touch ? 0u : 1u;
}

} // namespace

void BellpadSetInputState(BellpadInputSource source, const BellpadPadState& state) {
    std::scoped_lock lock(gInputMutex);
    gInputStates[sourceIndex(source)] = state;
}

void BellpadClearInputState(BellpadInputSource source) {
    BellpadSetInputState(source, {});
}

BellpadPadState BellpadGetMergedInputState() {
    std::scoped_lock lock(gInputMutex);
    const auto& touch = gInputStates[0];
    const auto& controller = gInputStates[1];

    BellpadPadState merged;
    merged.buttons = touch.buttons | controller.buttons;
    merged.stickX = strongestAxis(touch.stickX, controller.stickX);
    merged.stickY = strongestAxis(touch.stickY, controller.stickY);
    merged.cStickX = strongestAxis(touch.cStickX, controller.cStickX);
    merged.cStickY = strongestAxis(touch.cStickY, controller.cStickY);
    merged.triggerL = std::max(touch.triggerL, controller.triggerL);
    merged.triggerR = std::max(touch.triggerR, controller.triggerR);
    return merged;
}
