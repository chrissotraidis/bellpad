#include "BellpadInput.h"

#include <cassert>

int main() {
    BellpadPadState touch;
    touch.buttons = BellpadButtonA | BellpadButtonDPadLeft;
    touch.stickX = -90;
    touch.stickY = 32;
    touch.cStickX = 20;
    touch.triggerL = 200;

    BellpadPadState controller;
    controller.buttons = BellpadButtonB | BellpadButtonR;
    controller.stickX = 60;
    controller.stickY = -80;
    controller.cStickX = -70;
    controller.cStickY = 45;
    controller.triggerL = 100;
    controller.triggerR = 220;

    BellpadSetInputState(BellpadInputSource::Touch, touch);
    BellpadSetInputState(BellpadInputSource::Controller, controller);
    const BellpadPadState merged = BellpadGetMergedInputState();

    assert((merged.buttons & BellpadButtonA) != 0);
    assert((merged.buttons & BellpadButtonB) != 0);
    assert((merged.buttons & BellpadButtonR) != 0);
    assert((merged.buttons & BellpadButtonDPadLeft) != 0);
    assert(merged.stickX == -90);
    assert(merged.stickY == -80);
    assert(merged.cStickX == -70);
    assert(merged.cStickY == 45);
    assert(merged.triggerL == 200);
    assert(merged.triggerR == 220);

    BellpadClearInputState(BellpadInputSource::Touch);
    BellpadClearInputState(BellpadInputSource::Controller);
    const BellpadPadState cleared = BellpadGetMergedInputState();
    assert(cleared.buttons == 0);
    assert(cleared.stickX == 0 && cleared.stickY == 0);
    assert(cleared.cStickX == 0 && cleared.cStickY == 0);
    assert(cleared.triggerL == 0 && cleared.triggerR == 0);
    return 0;
}
