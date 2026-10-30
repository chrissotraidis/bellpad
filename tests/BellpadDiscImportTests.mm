#import <Foundation/Foundation.h>
#include <CommonCrypto/CommonDigest.h>
#include "BellpadDiscValidator.h"
#include <cassert>
#include <cstdio>

// Exercise the production transaction with the real validator and an explicitly
// synthetic fingerprint, without weakening or replacing the shipped fingerprint.
static BellpadDiscFingerprint fixtureFingerprint;
static bool corruptStaging = false;
static BellpadDiscValidationResult BPFixtureValidate(const std::filesystem::path &path) {
    if (corruptStaging && path.filename() == "Animal Crossing.importing.iso") {
        FILE *file = fopen(path.c_str(), "r+b");
        assert(file);
        fseek(file, 40, SEEK_SET); fputc(1, file); fclose(file);
    }
    return BellpadValidateDiscImage(path, fixtureFingerprint);
}
#define BellpadValidateDiscImage BPFixtureValidate
#import "../apple/ios/BellpadDiscImport.h"
#undef BellpadValidateDiscImage

static void Write(NSURL *url, NSData *data) {
    NSError *error = nil;
    assert([data writeToURL:url options:NSDataWritingAtomic error:&error]);
}

int main() {
    @autoreleasepool {
        NSFileManager *files = NSFileManager.defaultManager;
        NSURL *root = [files.temporaryDirectory URLByAppendingPathComponent:NSUUID.UUID.UUIDString isDirectory:YES];
        NSURL *documents = [root URLByAppendingPathComponent:@"Documents" isDirectory:YES];
        NSURL *support = [root URLByAppendingPathComponent:@"Application Support" isDirectory:YES];
        NSError *error = nil;
        NSURL *directory = BPPrepareDiscImportDirectory(documents, &error);
        assert(directory && !error);
        assert([files fileExistsAtPath:[directory URLByAppendingPathComponent:@"READ ME.txt"].path]);
        assert(!BPFindDiscInImportDirectory(directory, &error) && error);

        NSURL *fakeDirectory = [directory URLByAppendingPathComponent:@"folder.iso" isDirectory:YES];
        assert([files createDirectoryAtURL:fakeDirectory withIntermediateDirectories:YES attributes:nil error:nil]);
        error = nil;
        assert(!BPFindDiscInImportDirectory(directory, &error));

        NSMutableData *fixture = [NSMutableData dataWithLength:64];
        unsigned char *bytes = (unsigned char *)fixture.mutableBytes;
        memcpy(bytes, "GAFE01", 6);
        bytes[0x1c] = 0xc2; bytes[0x1d] = 0x33; bytes[0x1e] = 0x9f; bytes[0x1f] = 0x3d;
        fixtureFingerprint.payloadSize = fixture.length;
        fixtureFingerprint.fullImageSize = 128;
        CC_SHA256(fixture.bytes, (CC_LONG)fixture.length, fixtureFingerprint.payloadSha256.data());
        NSURL *source = [directory URLByAppendingPathComponent:@"Fixture.ISO"];
        Write(source, fixture);
        assert(!BellpadValidateDiscImage(source.fileSystemRepresentation).valid());
        error = nil;
        assert([BPFindDiscInImportDirectory(directory, &error).URLByResolvingSymlinksInPath.path isEqual:source.URLByResolvingSymlinksInPath.path] && !error);
        NSURL *second = [directory URLByAppendingPathComponent:@"second.gcm"];
        Write(second, fixture);
        assert(!BPFindDiscInImportDirectory(directory, &error));
        assert([error.localizedDescription containsString:@"More than one"]);
        [files removeItemAtURL:second error:nil];
        NSURL *symlink = [directory URLByAppendingPathComponent:@"linked.iso"];
        assert([files createSymbolicLinkAtURL:symlink withDestinationURL:source error:nil]);
        error = nil;
        assert([BPFindDiscInImportDirectory(directory, &error).URLByResolvingSymlinksInPath.path isEqual:source.URLByResolvingSymlinksInPath.path] && !error);

        error = nil;
        NSURL *retained = BPImportDiscImage(source, support, &error);
        assert(retained && !error);
        assert([[NSData dataWithContentsOfURL:source] isEqual:fixture]);
        assert([[NSData dataWithContentsOfURL:retained] isEqual:fixture]);
        // A second valid import exercises replacement of an existing retained image.
        assert(BPImportDiscImage(source, support, &error) && !error);

        NSData *marker = [@"previous retained image" dataUsingEncoding:NSUTF8StringEncoding];
        Write(retained, marker);
        corruptStaging = true;
        error = nil;
        assert(!BPImportDiscImage(source, support, &error) && error);
        assert([[NSData dataWithContentsOfURL:retained] isEqual:marker]);
        assert([[NSData dataWithContentsOfURL:source] isEqual:fixture]);
        assert(![files fileExistsAtPath:[[retained URLByDeletingLastPathComponent]
            URLByAppendingPathComponent:@"Animal Crossing.importing.iso"].path]);
        corruptStaging = false;
        Write(source, marker);
        error = nil;
        assert(!BPImportDiscImage(source, support, &error) && error);
        assert([[NSData dataWithContentsOfURL:retained] isEqual:marker]);
        assert([[NSData dataWithContentsOfURL:source] isEqual:marker]);
        error = nil;
        assert(!BPImportDiscImage(second, support, &error) && error);
        assert([[NSData dataWithContentsOfURL:retained] isEqual:marker]);

        BPRemoveImportedInboxCopy(source, documents);
        assert([files fileExistsAtPath:source.path]);
        NSURL *inbox = [documents URLByAppendingPathComponent:@"Inbox" isDirectory:YES];
        assert([files createDirectoryAtURL:inbox withIntermediateDirectories:YES attributes:nil error:nil]);
        NSURL *copy = [inbox URLByAppendingPathComponent:@"copy.iso"];
        Write(copy, fixture);
        BPRemoveImportedInboxCopy(copy, documents);
        assert(![files fileExistsAtPath:copy.path]);
        assert([files fileExistsAtPath:retained.path]);
        assert([files removeItemAtURL:root error:&error]);
        puts("Disc import: folder setup/empty/ambiguous/uppercase/directory/symlink; coordinated import/replacement; failed validation and missing source preserve retained data and original; staging cleanup; Inbox-only cleanup passed.");
    }
}
