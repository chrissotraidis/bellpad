#include "BellpadDiscValidator.h"
#include "BellpadInput.h"

#include <algorithm>
#include <array>
#include <cassert>
#include <chrono>
#include <filesystem>
#include <fstream>

namespace {

std::filesystem::path writeSyntheticHeader(std::array<std::uint8_t, 0x20> header, const char* extension) {
    const auto nonce = std::chrono::steady_clock::now().time_since_epoch().count();
    const auto path = std::filesystem::temp_directory_path() /
                      ("bellpad-disc-validator-" + std::to_string(nonce) + extension);
    std::ofstream stream(path, std::ios::binary);
    stream.write(reinterpret_cast<const char*>(header.data()), header.size());
    stream.close();
    return path;
}

} // namespace

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

    std::array<std::uint8_t, 0x20> header{};
    const char supportedId[] = "GAFE01";
    std::copy_n(reinterpret_cast<const std::uint8_t*>(supportedId), 6, header.begin());
    header[7] = 0;
    header[0x1C] = 0xC2;
    header[0x1D] = 0x33;
    header[0x1E] = 0x9F;
    header[0x1F] = 0x3D;

    const auto validPath = writeSyntheticHeader(header, ".iso");
    const auto valid = BellpadValidateDiscImage(validPath);
    assert(valid.valid());
    assert(valid.gameId == "GAFE01");
    assert(valid.revision == 0);
    std::filesystem::remove(validPath);

    header[7] = 1;
    const auto revisionPath = writeSyntheticHeader(header, ".gcm");
    assert(BellpadValidateDiscImage(revisionPath).code == BellpadDiscValidationCode::UnsupportedRevision);
    std::filesystem::remove(revisionPath);

    header[7] = 0;
    header[0] = 'X';
    const auto gamePath = writeSyntheticHeader(header, ".iso");
    assert(BellpadValidateDiscImage(gamePath).code == BellpadDiscValidationCode::UnsupportedGame);
    std::filesystem::remove(gamePath);

    const auto containerPath = writeSyntheticHeader(header, ".rvz");
    assert(BellpadValidateDiscImage(containerPath).code == BellpadDiscValidationCode::UnsupportedContainer);
    std::filesystem::remove(containerPath);
    return 0;
}
