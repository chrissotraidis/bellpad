#include "BellpadDiscValidator.h"
#include "BellpadInput.h"
#include "BellpadSaveData.h"

#include <algorithm>
#include <array>
#include <atomic>
#include <cassert>
#include <chrono>
#include <cstdlib>
#include <filesystem>
#include <fstream>
#include <thread>
#include <vector>

namespace {

std::filesystem::path writeSyntheticHeader(std::array<std::uint8_t, 0x20> header,
                                           const char* extension,
                                           std::size_t totalSize = 0x20) {
    assert(totalSize >= header.size());
    const auto nonce = std::chrono::steady_clock::now().time_since_epoch().count();
    const auto path = std::filesystem::temp_directory_path() /
                      ("bellpad-disc-validator-" + std::to_string(nonce) + extension);
    std::ofstream stream(path, std::ios::binary);
    stream.write(reinterpret_cast<const char*>(header.data()), header.size());
    std::vector<std::uint8_t> padding(totalSize - header.size());
    stream.write(reinterpret_cast<const char*>(padding.data()), padding.size());
    stream.close();
    return path;
}

bool sameState(const BellpadPadState& first, const BellpadPadState& second) {
    return first.buttons == second.buttons &&
           first.stickX == second.stickX && first.stickY == second.stickY &&
           first.cStickX == second.cStickX && first.cStickY == second.cStickY &&
           first.triggerL == second.triggerL && first.triggerR == second.triggerR;
}

} // namespace

int main() {
    static_assert(sizeof(BellpadPadState) == 8);
    static_assert(BellpadButtonDPadLeft == 0x0001);
    static_assert(BellpadButtonDPadRight == 0x0002);
    static_assert(BellpadButtonDPadDown == 0x0004);
    static_assert(BellpadButtonDPadUp == 0x0008);
    static_assert(BellpadButtonZ == 0x0010);
    static_assert(BellpadButtonR == 0x0020);
    static_assert(BellpadButtonL == 0x0040);
    static_assert(BellpadButtonA == 0x0100);
    static_assert(BellpadButtonB == 0x0200);
    static_assert(BellpadButtonX == 0x0400);
    static_assert(BellpadButtonY == 0x0800);
    static_assert(BellpadButtonStart == 0x1000);

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

    BellpadPadState copied;
    assert(bellpad_copy_normalized_pad_state(
        &copied.buttons, &copied.stickX, &copied.stickY,
        &copied.cStickX, &copied.cStickY,
        &copied.triggerL, &copied.triggerR) == 1);
    assert(copied.buttons == merged.buttons);
    assert(copied.stickX == merged.stickX);
    assert(copied.stickY == merged.stickY);
    assert(copied.cStickX == merged.cStickX);
    assert(copied.cStickY == merged.cStickY);
    assert(copied.triggerL == merged.triggerL);
    assert(copied.triggerR == merged.triggerR);
    assert(bellpad_copy_normalized_pad_state(
        nullptr, &copied.stickX, &copied.stickY,
        &copied.cStickX, &copied.cStickY,
        &copied.triggerL, &copied.triggerR) == 0);

    BellpadClearInputState(BellpadInputSource::Touch);
    BellpadClearInputState(BellpadInputSource::Controller);
    const BellpadPadState cleared = BellpadGetMergedInputState();
    assert(cleared.buttons == 0);
    assert(cleared.stickX == 0 && cleared.stickY == 0);
    assert(cleared.cStickX == 0 && cleared.cStickY == 0);
    assert(cleared.triggerL == 0 && cleared.triggerR == 0);
    assert(bellpad_copy_normalized_pad_state(
        &copied.buttons, &copied.stickX, &copied.stickY,
        &copied.cStickX, &copied.cStickY,
        &copied.triggerL, &copied.triggerR) == 1);
    assert(copied.buttons == 0);

    BellpadPadState quickTap;
    quickTap.buttons = BellpadButtonA;
    BellpadSetInputState(BellpadInputSource::Touch, quickTap);
    BellpadSetInputState(BellpadInputSource::Touch, {});
    assert(bellpad_copy_normalized_pad_state(
        &copied.buttons, &copied.stickX, &copied.stickY,
        &copied.cStickX, &copied.cStickY,
        &copied.triggerL, &copied.triggerR) == 1);
    assert(copied.buttons == BellpadButtonA);
    assert(bellpad_copy_normalized_pad_state(
        &copied.buttons, &copied.stickX, &copied.stickY,
        &copied.cStickX, &copied.cStickY,
        &copied.triggerL, &copied.triggerR) == 1);
    assert(copied.buttons == 0);

    BellpadPadState alternate = touch;
    alternate.buttons = BellpadButtonY | BellpadButtonDPadRight;
    alternate.stickX = 75;
    alternate.stickY = -45;
    alternate.cStickX = -31;
    alternate.cStickY = 88;
    alternate.triggerL = 9;
    alternate.triggerR = 240;
    std::atomic<bool> startConcurrentCopy = false;
    std::thread writer([&] {
        while (!startConcurrentCopy.load(std::memory_order_acquire)) {
        }
        for (int index = 0; index < 10'000; ++index) {
            BellpadSetInputState(BellpadInputSource::Touch, (index & 1) ? touch : alternate);
        }
    });
    startConcurrentCopy.store(true, std::memory_order_release);
    for (int index = 0; index < 10'000; ++index) {
        BellpadPadState concurrent;
        assert(bellpad_copy_normalized_pad_state(
            &concurrent.buttons, &concurrent.stickX, &concurrent.stickY,
            &concurrent.cStickX, &concurrent.cStickY,
            &concurrent.triggerL, &concurrent.triggerR) == 1);
        BellpadPadState touchWithLatchedButtons = touch;
        touchWithLatchedButtons.buttons |= alternate.buttons;
        BellpadPadState alternateWithLatchedButtons = alternate;
        alternateWithLatchedButtons.buttons |= touch.buttons;
        assert(sameState(concurrent, {}) || sameState(concurrent, touch) ||
               sameState(concurrent, alternate) || sameState(concurrent, touchWithLatchedButtons) ||
               sameState(concurrent, alternateWithLatchedButtons));
    }
    writer.join();
    BellpadClearInputState(BellpadInputSource::Touch);

    std::array<std::uint8_t, 0x20> header{};
    const char supportedId[] = "GAFE01";
    std::copy_n(reinterpret_cast<const std::uint8_t*>(supportedId), 6, header.begin());
    header[7] = 0;
    header[0x1C] = 0xC2;
    header[0x1D] = 0x33;
    header[0x1E] = 0x9F;
    header[0x1F] = 0x3D;

    constexpr std::array<std::uint8_t, 32> syntheticHeaderSha256{
        0xFA, 0x1C, 0xCF, 0x9C, 0xC0, 0x95, 0x3F, 0xBF,
        0x63, 0xE2, 0x44, 0x0F, 0x85, 0xD2, 0xC3, 0xB8,
        0x6C, 0x5B, 0x90, 0x8A, 0x0D, 0x56, 0x0C, 0xD1,
        0x38, 0xCB, 0xB1, 0x51, 0x57, 0x20, 0xE9, 0xB4,
    };
    const BellpadDiscFingerprint syntheticFingerprint{0x20, 0x40, syntheticHeaderSha256};

    const auto validPath = writeSyntheticHeader(header, ".iso");
    assert(BellpadValidateDiscImage(validPath).code == BellpadDiscValidationCode::UnsupportedSize);
    const auto valid = BellpadValidateDiscImage(validPath, syntheticFingerprint);
    assert(valid.valid());
    assert(valid.gameId == "GAFE01");
    assert(valid.revision == 0);
    assert(valid.payloadSha256 == "fa1ccf9cc0953fbf63e2440f85d2c3b86c5b908a0d560cd138cbb1515720e9b4");
    std::filesystem::remove(validPath);

    const auto fullPath = writeSyntheticHeader(header, ".gcm", 0x40);
    assert(BellpadValidateDiscImage(fullPath, syntheticFingerprint).valid());
    std::filesystem::remove(fullPath);

    BellpadDiscFingerprint wrongFingerprint = syntheticFingerprint;
    wrongFingerprint.payloadSha256.back() ^= 1;
    const auto mismatchPath = writeSyntheticHeader(header, ".iso");
    assert(BellpadValidateDiscImage(mismatchPath, wrongFingerprint).code ==
           BellpadDiscValidationCode::HashMismatch);
    std::filesystem::remove(mismatchPath);

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

    if (const char* retailImage = std::getenv("BELLPAD_TEST_DISC_IMAGE")) {
        const auto retailResult = BellpadValidateDiscImage(retailImage);
        assert(retailResult.valid());
        assert(retailResult.fileSize == 27'573'708 || retailResult.fileSize == 1'459'978'240);
        assert(retailResult.payloadSha256 ==
               "7bdc4fcf4a209521ba59d8fc850bc5b5d21ea96002a225224e83e3efe52d4615");
    }

    std::vector<std::uint8_t> gci(BellpadExpectedGCISize);
    std::copy_n(reinterpret_cast<const std::uint8_t*>(supportedId), 6, gci.begin());
    gci[0x38] = 0;
    gci[0x39] = 0x39;
    constexpr std::size_t saveOffset = 0x40 + 0x26000;
    gci[saveOffset + 3] = 6;
    gci[saveOffset + 4] = 'G';
    gci[saveOffset + 5] = 'A';
    gci[saveOffset + 6] = 'F';
    gci[saveOffset + 7] = 'E';
    gci[saveOffset + 8] = 0x30;
    gci[saveOffset + 9] = 0x01;
    std::uint32_t gciSum = 0;
    for (std::size_t index = 0; index < 0x242A0; index += 2) {
        gciSum += (static_cast<std::uint16_t>(gci[saveOffset + index]) << 8) |
                  gci[saveOffset + index + 1];
    }
    const std::uint16_t gciChecksum = static_cast<std::uint16_t>(0u - gciSum);
    gci[saveOffset + 0x12] = static_cast<std::uint8_t>(gciChecksum >> 8);
    gci[saveOffset + 0x13] = static_cast<std::uint8_t>(gciChecksum);
    assert(BellpadValidateGCI(gci.data(), gci.size()).valid());

    gci[saveOffset + 0x20] ^= 1;
    assert(BellpadValidateGCI(gci.data(), gci.size()).code == BellpadGCIValidationCode::InvalidChecksum);
    gci[saveOffset + 0x20] ^= 1;
    gci[saveOffset + 3] = 7;
    assert(BellpadValidateGCI(gci.data(), gci.size()).code == BellpadGCIValidationCode::UnsupportedVersion);
    gci[saveOffset + 3] = 6;
    gci[saveOffset + 8] = 0;
    assert(BellpadValidateGCI(gci.data(), gci.size()).code == BellpadGCIValidationCode::InvalidTownId);
    assert(BellpadValidateGCI(gci.data(), gci.size() - 1).code == BellpadGCIValidationCode::WrongSize);
    return 0;
}
