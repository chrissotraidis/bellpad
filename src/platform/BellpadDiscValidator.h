#pragma once

#include <array>
#include <cstdint>
#include <filesystem>
#include <string>

enum class BellpadDiscValidationCode {
    Valid,
    CannotOpen,
    TooSmall,
    UnsupportedContainer,
    InvalidMagic,
    UnsupportedGame,
    UnsupportedRevision,
    UnsupportedSize,
    HashMismatch,
};

struct BellpadDiscFingerprint {
    std::uintmax_t payloadSize = 0;
    std::uintmax_t fullImageSize = 0;
    std::array<std::uint8_t, 32> payloadSha256{};
};

struct BellpadDiscValidationResult {
    BellpadDiscValidationCode code = BellpadDiscValidationCode::CannotOpen;
    std::string gameId;
    std::uint8_t revision = 0;
    std::uintmax_t fileSize = 0;
    std::string payloadSha256;

    bool valid() const { return code == BellpadDiscValidationCode::Valid; }
};

BellpadDiscValidationResult BellpadValidateDiscImage(const std::filesystem::path& path);
BellpadDiscValidationResult BellpadValidateDiscImage(
    const std::filesystem::path& path,
    const BellpadDiscFingerprint& fingerprint);
std::string BellpadDiscValidationMessage(const BellpadDiscValidationResult& result);
