#pragma once

#include <cstddef>
#include <cstdint>
#include <string>

enum class BellpadGCIValidationCode {
    Valid,
    WrongSize,
    UnsupportedGame,
    InvalidBlockCount,
    UnsupportedVersion,
    InvalidTownCode,
    InvalidTownId,
    InvalidChecksum,
};

struct BellpadGCIValidationResult {
    BellpadGCIValidationCode code = BellpadGCIValidationCode::WrongSize;
    std::uint32_t version = 0;
    std::uint16_t townId = 0;

    bool valid() const { return code == BellpadGCIValidationCode::Valid; }
};

constexpr std::size_t BellpadExpectedGCISize = 0x40 + 0x72000;

BellpadGCIValidationResult BellpadValidateGCI(const std::uint8_t* data, std::size_t size);
std::string BellpadGCIValidationMessage(const BellpadGCIValidationResult& result);
