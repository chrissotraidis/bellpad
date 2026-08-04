#include "BellpadDiscValidator.h"

#include <algorithm>
#include <array>
#include <cctype>
#include <cstring>
#include <fstream>
#include <iomanip>
#include <sstream>

namespace {

constexpr std::array<std::uint8_t, 4> kGameCubeMagic{0xC2, 0x33, 0x9F, 0x3D};
constexpr char kSupportedGameId[] = "GAFE01";
constexpr BellpadDiscFingerprint kSupportedFingerprint{
    27'573'708,
    1'459'978'240,
    {0x7B, 0xDC, 0x4F, 0xCF, 0x4A, 0x20, 0x95, 0x21,
     0xBA, 0x59, 0xD8, 0xFC, 0x85, 0x0B, 0xC5, 0xB5,
     0xD2, 0x1E, 0xA9, 0x60, 0x02, 0xA2, 0x25, 0x22,
     0x4E, 0x83, 0xE3, 0xEF, 0xE5, 0x2D, 0x46, 0x15},
};

constexpr std::array<std::uint32_t, 64> kSha256RoundConstants{
    0x428A2F98, 0x71374491, 0xB5C0FBCF, 0xE9B5DBA5, 0x3956C25B, 0x59F111F1, 0x923F82A4, 0xAB1C5ED5,
    0xD807AA98, 0x12835B01, 0x243185BE, 0x550C7DC3, 0x72BE5D74, 0x80DEB1FE, 0x9BDC06A7, 0xC19BF174,
    0xE49B69C1, 0xEFBE4786, 0x0FC19DC6, 0x240CA1CC, 0x2DE92C6F, 0x4A7484AA, 0x5CB0A9DC, 0x76F988DA,
    0x983E5152, 0xA831C66D, 0xB00327C8, 0xBF597FC7, 0xC6E00BF3, 0xD5A79147, 0x06CA6351, 0x14292967,
    0x27B70A85, 0x2E1B2138, 0x4D2C6DFC, 0x53380D13, 0x650A7354, 0x766A0ABB, 0x81C2C92E, 0x92722C85,
    0xA2BFE8A1, 0xA81A664B, 0xC24B8B70, 0xC76C51A3, 0xD192E819, 0xD6990624, 0xF40E3585, 0x106AA070,
    0x19A4C116, 0x1E376C08, 0x2748774C, 0x34B0BCB5, 0x391C0CB3, 0x4ED8AA4A, 0x5B9CCA4F, 0x682E6FF3,
    0x748F82EE, 0x78A5636F, 0x84C87814, 0x8CC70208, 0x90BEFFFA, 0xA4506CEB, 0xBEF9A3F7, 0xC67178F2,
};

class Sha256 {
public:
    void update(const std::uint8_t* data, std::size_t size) {
        _totalBytes += size;
        while (size > 0) {
            const std::size_t copied = std::min(size, _block.size() - _blockSize);
            std::memcpy(_block.data() + _blockSize, data, copied);
            _blockSize += copied;
            data += copied;
            size -= copied;
            if (_blockSize == _block.size()) {
                transform(_block.data());
                _blockSize = 0;
            }
        }
    }

    std::array<std::uint8_t, 32> finish() {
        const std::uint64_t totalBits = _totalBytes * 8;
        _block[_blockSize++] = 0x80;
        if (_blockSize > 56) {
            std::fill(_block.begin() + _blockSize, _block.end(), 0);
            transform(_block.data());
            _blockSize = 0;
        }
        std::fill(_block.begin() + _blockSize, _block.begin() + 56, 0);
        for (std::size_t index = 0; index < 8; ++index) {
            _block[63 - index] = static_cast<std::uint8_t>(totalBits >> (index * 8));
        }
        transform(_block.data());

        std::array<std::uint8_t, 32> digest{};
        for (std::size_t index = 0; index < _state.size(); ++index) {
            digest[index * 4] = static_cast<std::uint8_t>(_state[index] >> 24);
            digest[index * 4 + 1] = static_cast<std::uint8_t>(_state[index] >> 16);
            digest[index * 4 + 2] = static_cast<std::uint8_t>(_state[index] >> 8);
            digest[index * 4 + 3] = static_cast<std::uint8_t>(_state[index]);
        }
        return digest;
    }

private:
    static std::uint32_t rotateRight(std::uint32_t value, unsigned count) {
        return (value >> count) | (value << (32 - count));
    }

    void transform(const std::uint8_t* block) {
        std::array<std::uint32_t, 64> words{};
        for (std::size_t index = 0; index < 16; ++index) {
            words[index] = (static_cast<std::uint32_t>(block[index * 4]) << 24) |
                           (static_cast<std::uint32_t>(block[index * 4 + 1]) << 16) |
                           (static_cast<std::uint32_t>(block[index * 4 + 2]) << 8) |
                           static_cast<std::uint32_t>(block[index * 4 + 3]);
        }
        for (std::size_t index = 16; index < words.size(); ++index) {
            const std::uint32_t s0 = rotateRight(words[index - 15], 7) ^
                                     rotateRight(words[index - 15], 18) ^ (words[index - 15] >> 3);
            const std::uint32_t s1 = rotateRight(words[index - 2], 17) ^
                                     rotateRight(words[index - 2], 19) ^ (words[index - 2] >> 10);
            words[index] = words[index - 16] + s0 + words[index - 7] + s1;
        }

        std::uint32_t a = _state[0];
        std::uint32_t b = _state[1];
        std::uint32_t c = _state[2];
        std::uint32_t d = _state[3];
        std::uint32_t e = _state[4];
        std::uint32_t f = _state[5];
        std::uint32_t g = _state[6];
        std::uint32_t h = _state[7];
        for (std::size_t index = 0; index < words.size(); ++index) {
            const std::uint32_t sum1 = rotateRight(e, 6) ^ rotateRight(e, 11) ^ rotateRight(e, 25);
            const std::uint32_t choice = (e & f) ^ (~e & g);
            const std::uint32_t temp1 = h + sum1 + choice + kSha256RoundConstants[index] + words[index];
            const std::uint32_t sum0 = rotateRight(a, 2) ^ rotateRight(a, 13) ^ rotateRight(a, 22);
            const std::uint32_t majority = (a & b) ^ (a & c) ^ (b & c);
            const std::uint32_t temp2 = sum0 + majority;
            h = g;
            g = f;
            f = e;
            e = d + temp1;
            d = c;
            c = b;
            b = a;
            a = temp1 + temp2;
        }
        _state[0] += a;
        _state[1] += b;
        _state[2] += c;
        _state[3] += d;
        _state[4] += e;
        _state[5] += f;
        _state[6] += g;
        _state[7] += h;
    }

    std::array<std::uint32_t, 8> _state{
        0x6A09E667, 0xBB67AE85, 0x3C6EF372, 0xA54FF53A,
        0x510E527F, 0x9B05688C, 0x1F83D9AB, 0x5BE0CD19,
    };
    std::array<std::uint8_t, 64> _block{};
    std::size_t _blockSize = 0;
    std::uint64_t _totalBytes = 0;
};

std::string hexDigest(const std::array<std::uint8_t, 32>& digest) {
    std::ostringstream text;
    text << std::hex << std::setfill('0');
    for (const std::uint8_t byte : digest) text << std::setw(2) << static_cast<unsigned>(byte);
    return text.str();
}

bool hashPrefix(std::ifstream& stream,
                std::uintmax_t byteCount,
                std::array<std::uint8_t, 32>& digest) {
    stream.clear();
    stream.seekg(0, std::ios::beg);
    if (!stream) return false;

    Sha256 sha256;
    std::array<std::uint8_t, 64 * 1024> buffer{};
    while (byteCount > 0) {
        const std::size_t requested = static_cast<std::size_t>(
            std::min<std::uintmax_t>(byteCount, buffer.size()));
        if (!stream.read(reinterpret_cast<char*>(buffer.data()), requested)) return false;
        sha256.update(buffer.data(), requested);
        byteCount -= requested;
    }
    digest = sha256.finish();
    return true;
}

std::string lowercaseExtension(const std::filesystem::path& path) {
    std::string extension = path.extension().string();
    std::transform(extension.begin(), extension.end(), extension.begin(), [](unsigned char value) {
        return static_cast<char>(std::tolower(value));
    });
    return extension;
}

} // namespace

BellpadDiscValidationResult BellpadValidateDiscImage(const std::filesystem::path& path) {
    return BellpadValidateDiscImage(path, kSupportedFingerprint);
}

BellpadDiscValidationResult BellpadValidateDiscImage(
    const std::filesystem::path& path,
    const BellpadDiscFingerprint& fingerprint) {
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
        return result;
    } else if (result.gameId != kSupportedGameId) {
        result.code = BellpadDiscValidationCode::UnsupportedGame;
        return result;
    } else if (result.revision != 0) {
        result.code = BellpadDiscValidationCode::UnsupportedRevision;
        return result;
    }

    if (result.fileSize != fingerprint.payloadSize &&
        result.fileSize != fingerprint.fullImageSize) {
        result.code = BellpadDiscValidationCode::UnsupportedSize;
        return result;
    }

    std::array<std::uint8_t, 32> digest{};
    if (fingerprint.payloadSize < header.size() ||
        fingerprint.payloadSize > result.fileSize ||
        !hashPrefix(stream, fingerprint.payloadSize, digest)) {
        result.code = BellpadDiscValidationCode::CannotOpen;
        return result;
    }
    result.payloadSha256 = hexDigest(digest);
    result.code = digest == fingerprint.payloadSha256
        ? BellpadDiscValidationCode::Valid
        : BellpadDiscValidationCode::HashMismatch;
    return result;
}

std::string BellpadDiscValidationMessage(const BellpadDiscValidationResult& result) {
    switch (result.code) {
    case BellpadDiscValidationCode::Valid: {
        std::ostringstream message;
        message << "Supported " << result.gameId << " revision " << static_cast<unsigned>(result.revision)
                << " image with verified content fingerprint.";
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
    case BellpadDiscValidationCode::UnsupportedSize:
        return "This GAFE01 image has an unsupported size. Bellpad accepts the verified full retail image or its exact trimmed payload form.";
    case BellpadDiscValidationCode::HashMismatch:
        return "This GAFE01 image does not match the supported revision's content fingerprint.";
    }
    return "Unknown disc validation result.";
}
