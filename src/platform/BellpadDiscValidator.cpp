#include "BellpadDiscValidator.h"

#include <algorithm>
#include <array>
#include <cctype>
#include <fstream>
#include <sstream>

namespace {

constexpr std::array<std::uint8_t, 4> kGameCubeMagic{0xC2, 0x33, 0x9F, 0x3D};
constexpr char kSupportedGameId[] = "GAFE01";

std::string lowercaseExtension(const std::filesystem::path& path) {
    std::string extension = path.extension().string();
    std::transform(extension.begin(), extension.end(), extension.begin(), [](unsigned char value) {
        return static_cast<char>(std::tolower(value));
    });
    return extension;
}

} // namespace

BellpadDiscValidationResult BellpadValidateDiscImage(const std::filesystem::path& path) {
    BellpadDiscValidationResult result;
    const std::string extension = lowercaseExtension(path);
    if (extension != ".iso" && extension != ".gcm") {
        result.code = BellpadDiscValidationCode::UnsupportedContainer;
        return result;
    }

    std::error_code sizeError;
    result.fileSize = std::filesystem::file_size(path, sizeError);
    if (sizeError) {
        result.code = BellpadDiscValidationCode::CannotOpen;
        return result;
    }
    if (result.fileSize < 0x20) {
        result.code = BellpadDiscValidationCode::TooSmall;
        return result;
    }

    std::ifstream stream(path, std::ios::binary);
    std::array<std::uint8_t, 0x20> header{};
    if (!stream.read(reinterpret_cast<char*>(header.data()), header.size())) {
        result.code = BellpadDiscValidationCode::CannotOpen;
        return result;
    }

    result.gameId.assign(reinterpret_cast<const char*>(header.data()), 6);
    result.revision = header[7];
    if (!std::equal(kGameCubeMagic.begin(), kGameCubeMagic.end(), header.begin() + 0x1C)) {
        result.code = BellpadDiscValidationCode::InvalidMagic;
    } else if (result.gameId != kSupportedGameId) {
        result.code = BellpadDiscValidationCode::UnsupportedGame;
    } else if (result.revision != 0) {
        result.code = BellpadDiscValidationCode::UnsupportedRevision;
    } else {
        result.code = BellpadDiscValidationCode::Valid;
    }
    return result;
}

std::string BellpadDiscValidationMessage(const BellpadDiscValidationResult& result) {
    switch (result.code) {
    case BellpadDiscValidationCode::Valid: {
        std::ostringstream message;
        message << "Supported " << result.gameId << " revision " << static_cast<unsigned>(result.revision)
                << " image.";
        return message.str();
    }
    case BellpadDiscValidationCode::CannotOpen:
        return "Bellpad could not read the selected file.";
    case BellpadDiscValidationCode::TooSmall:
        return "The selected file is too small to be a GameCube image.";
    case BellpadDiscValidationCode::UnsupportedContainer:
        return "This build validates uncompressed ISO or GCM images only.";
    case BellpadDiscValidationCode::InvalidMagic:
        return "The selected file does not have a valid GameCube disc header.";
    case BellpadDiscValidationCode::UnsupportedGame:
        return "Unsupported game ID " + (result.gameId.empty() ? std::string("(unknown)") : result.gameId) + ".";
    case BellpadDiscValidationCode::UnsupportedRevision:
        return "Game revision " + std::to_string(result.revision) + " is not supported; Bellpad currently requires revision 0.";
    }
    return "Unknown disc validation result.";
}
