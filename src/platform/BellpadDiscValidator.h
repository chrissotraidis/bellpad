#pragma once

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
};

struct BellpadDiscValidationResult {
    BellpadDiscValidationCode code = BellpadDiscValidationCode::CannotOpen;
    std::string gameId;
    std::uint8_t revision = 0;
    std::uintmax_t fileSize = 0;

    bool valid() const { return code == BellpadDiscValidationCode::Valid; }
};

BellpadDiscValidationResult BellpadValidateDiscImage(const std::filesystem::path& path);
std::string BellpadDiscValidationMessage(const BellpadDiscValidationResult& result);
