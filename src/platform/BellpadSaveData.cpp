#include "BellpadSaveData.h"

#include <cstring>

namespace {

constexpr std::size_t kHeaderSize = 0x40;
constexpr std::size_t kDataSize = 0x72000;
constexpr std::size_t kSaveOffset = kHeaderSize + 0x26000;
constexpr std::size_t kSaveChecksumSize = 0x242A0;

std::uint16_t readBE16(const std::uint8_t* data) {
    return static_cast<std::uint16_t>((static_cast<std::uint16_t>(data[0]) << 8) | data[1]);
}

std::uint32_t readBE32(const std::uint8_t* data) {
    return (static_cast<std::uint32_t>(data[0]) << 24) |
           (static_cast<std::uint32_t>(data[1]) << 16) |
           (static_cast<std::uint32_t>(data[2]) << 8) |
           static_cast<std::uint32_t>(data[3]);
}

} // namespace

BellpadGCIValidationResult BellpadValidateGCI(const std::uint8_t* data, std::size_t size) {
    BellpadGCIValidationResult result;
    if (!data || size != BellpadExpectedGCISize) {
        result.code = BellpadGCIValidationCode::WrongSize;
        return result;
    }
    if (std::memcmp(data, "GAFE01", 6) != 0) {
        result.code = BellpadGCIValidationCode::UnsupportedGame;
        return result;
    }
    if (readBE16(data + 0x38) != kDataSize / 0x2000) {
        result.code = BellpadGCIValidationCode::InvalidBlockCount;
        return result;
    }

    const std::uint8_t* save = data + kSaveOffset;
    result.version = readBE32(save);
    if (result.version != 5 && result.version != 6) {
        result.code = BellpadGCIValidationCode::UnsupportedVersion;
        return result;
    }
    if (std::memcmp(save + 4, "GAFE", 4) != 0) {
        result.code = BellpadGCIValidationCode::InvalidTownCode;
        return result;
    }
    result.townId = readBE16(save + 8);
    if ((result.townId & 0x3000u) != 0x3000u) {
        result.code = BellpadGCIValidationCode::InvalidTownId;
        return result;
    }

    std::uint32_t checksum = 0;
    for (std::size_t index = 0; index < kSaveChecksumSize; index += 2) {
        checksum += readBE16(save + index);
    }
    result.code = (checksum & 0xFFFFu) == 0
        ? BellpadGCIValidationCode::Valid
        : BellpadGCIValidationCode::InvalidChecksum;
    return result;
}

std::string BellpadGCIValidationMessage(const BellpadGCIValidationResult& result) {
    switch (result.code) {
    case BellpadGCIValidationCode::Valid:
        return "Supported Animal Crossing GAFE01 GCI save.";
    case BellpadGCIValidationCode::WrongSize:
        return "The selected file is not a 467,008-byte Animal Crossing GCI save.";
    case BellpadGCIValidationCode::UnsupportedGame:
        return "The selected GCI is not an Animal Crossing GAFE01 save.";
    case BellpadGCIValidationCode::InvalidBlockCount:
        return "The selected GCI has an invalid memory-card block count.";
    case BellpadGCIValidationCode::UnsupportedVersion:
        return "The selected GCI uses an unsupported Animal Crossing save version.";
    case BellpadGCIValidationCode::InvalidTownCode:
        return "The selected GCI does not contain GAFE town data.";
    case BellpadGCIValidationCode::InvalidTownId:
        return "The selected GCI contains an invalid town identifier.";
    case BellpadGCIValidationCode::InvalidChecksum:
        return "The selected GCI failed its town-data checksum.";
    }
    return "Unknown GCI validation result.";
}
