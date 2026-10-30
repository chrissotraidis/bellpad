#pragma once

#import <Foundation/Foundation.h>
#include "BellpadDiscValidator.h"

// Shared by the playable app and the validation shell. Call coordinated reads
// on a worker queue: a file provider may need to download the selected item.
static inline NSError *BPDiscImportError(NSString *message) {
    return [NSError errorWithDomain:@"dev.bellpad.import" code:1
                          userInfo:@{NSLocalizedDescriptionKey: message}];
}

static inline NSURL *BPPrepareDiscImportDirectory(NSURL *documents, NSError **error) {
    NSURL *directory = [documents URLByAppendingPathComponent:@"Import" isDirectory:YES];
    NSFileManager *files = NSFileManager.defaultManager;
    if (![files createDirectoryAtURL:directory withIntermediateDirectories:YES attributes:nil error:error]) return nil;
    NSURL *instructions = [directory URLByAppendingPathComponent:@"READ ME.txt"];
    if (![files fileExistsAtPath:instructions.path]) {
        NSString *text = @"BellPad game data import\n\n"
            "Copy one legally obtained Animal Crossing USA revision 0 .iso or .gcm into this folder. "
            "Return to BellPad and tap Import from BellPad folder.\n\n"
            "BellPad validates the image before retaining a private copy. The original stays here; "
            "you can remove it after a successful import to recover space. Saves are kept separately.\n"
            "Compressed RVZ, CISO and NKit images must be converted to an uncompressed ISO first.\n";
        if (![text writeToURL:instructions atomically:YES encoding:NSUTF8StringEncoding error:error]) return nil;
    }
    return directory;
}

static inline NSURL *BPFindDiscInImportDirectory(NSURL *directory, NSError **error) {
    NSArray<NSURL *> *entries = [NSFileManager.defaultManager contentsOfDirectoryAtURL:directory
        includingPropertiesForKeys:@[NSURLIsRegularFileKey, NSURLIsSymbolicLinkKey]
        options:NSDirectoryEnumerationSkipsHiddenFiles error:error];
    if (!entries) return nil;
    NSMutableArray<NSURL *> *candidates = [NSMutableArray new];
    for (NSURL *entry in entries) {
        NSString *extension = entry.pathExtension.lowercaseString;
        if (![extension isEqualToString:@"iso"] && ![extension isEqualToString:@"gcm"]) continue;
        NSNumber *regular = nil, *symlink = nil;
        if (![entry getResourceValue:&regular forKey:NSURLIsRegularFileKey error:error] ||
            ![entry getResourceValue:&symlink forKey:NSURLIsSymbolicLinkKey error:error]) return nil;
        if (regular.boolValue && !symlink.boolValue) [candidates addObject:entry];
    }
    if (candidates.count != 1) {
        if (error) *error = BPDiscImportError(candidates.count == 0
            ? @"No ISO or GCM found. In Files, copy your image into On My iPhone/iPad → BellPad → Import, then try again."
            : @"More than one ISO or GCM is in BellPad → Import. Leave only the image you want to import, then try again.");
        return nil;
    }
    return candidates.firstObject;
}

static inline void BPCoordinateDiscRead(NSURL *source, NSError **error, void (^accessor)(NSURL *url)) {
    // A false return can also mean an app-owned copy which needs no scope.
    BOOL accessed = [source startAccessingSecurityScopedResource];
    NSFileCoordinator *coordinator = [[NSFileCoordinator alloc] initWithFilePresenter:nil];
    [coordinator coordinateReadingItemAtURL:source options:0 error:error byAccessor:accessor];
    if (accessed) [source stopAccessingSecurityScopedResource];
}

static inline NSURL *BPImportDiscImage(NSURL *source, NSURL *support, NSError **error) {
    NSFileManager *files = NSFileManager.defaultManager;
    NSURL *directory = [support URLByAppendingPathComponent:@"Game Data" isDirectory:YES];
    NSURL *destination = [directory URLByAppendingPathComponent:@"Animal Crossing.iso"];
    NSURL *staging = [directory URLByAppendingPathComponent:@"Animal Crossing.importing.iso"];
    __block NSError *importError = nil;
    NSError *coordinationError = nil;
    __block BOOL copied = NO;
    __block BOOL attemptedCopy = NO;
    BPCoordinateDiscRead(source, &coordinationError, ^(NSURL *readableURL) {
        const auto result = BellpadValidateDiscImage(readableURL.fileSystemRepresentation);
        if (!result.valid()) {
            importError = BPDiscImportError([NSString stringWithUTF8String:BellpadDiscValidationMessage(result).c_str()]);
            return;
        }
        if (![files createDirectoryAtURL:directory withIntermediateDirectories:YES attributes:nil error:&importError]) return;
        if ([files fileExistsAtPath:staging.path] && ![files removeItemAtURL:staging error:&importError]) return;
        attemptedCopy = YES;
        copied = [files copyItemAtURL:readableURL toURL:staging error:&importError];
    });
    if (!importError) importError = coordinationError;
    if (!importError && !copied) importError = BPDiscImportError(@"The file provider did not supply the image. Download it in Files or use BellPad → Import.");
    if (!importError && !BellpadValidateDiscImage(staging.fileSystemRepresentation).valid()) {
        importError = BPDiscImportError(@"The copied image failed validation. The previous game data was kept. Please copy the complete image again.");
    }
    if (!importError) {
        if ([files fileExistsAtPath:destination.path]) {
            [files replaceItemAtURL:destination withItemAtURL:staging backupItemName:nil
                           options:0 resultingItemURL:nil error:&importError];
        } else {
            [files moveItemAtURL:staging toURL:destination error:&importError];
        }
    }
    if (importError) {
        if (attemptedCopy) [files removeItemAtURL:staging error:nil];
        if (error) *error = importError;
        return nil;
    }
    return destination;
}

// The copy-mode picker may leave a copy in our Inbox. Only remove that copy
// after the import attempt, never the user's selected original or manual Import file.
static inline void BPRemoveImportedInboxCopy(NSURL *source, NSURL *documents) {
    NSURL *inbox = [documents URLByAppendingPathComponent:@"Inbox" isDirectory:YES];
    NSString *parent = source.URLByDeletingLastPathComponent.URLByResolvingSymlinksInPath.path;
    if ([parent isEqualToString:inbox.URLByResolvingSymlinksInPath.path]) {
        [NSFileManager.defaultManager removeItemAtURL:source error:nil];
    }
}
