/* PCAppleDiscMemoryTests.m - Bellpad's remembered macOS disc reference.
 *
 * The fixture is a locally generated placeholder file. This test contains no
 * game data and never reads a real disc image. */
#import <Foundation/Foundation.h>

#include "pc_apple.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

static int failures = 0;

static void check(int condition, const char* what) {
    printf("%s %s\n", condition ? "ok  " : "FAIL", what);
    if (!condition) failures++;
}

/* Bookmark resolution returns a canonical path, so /var resolves to
 * /private/var. Compare both sides after the same canonicalization. */
static int same_file_path(const char* resolved, NSString* expected) {
    char canonical[PATH_MAX];

    if (realpath(expected.fileSystemRepresentation, canonical) == NULL) return 0;
    return strcmp(resolved, canonical) == 0;
}

int main(void) {
    @autoreleasepool {
        NSFileManager* files = NSFileManager.defaultManager;
        NSString* home = [NSTemporaryDirectory()
            stringByAppendingPathComponent:@"bellpad-disc-memory-tests"];
        [files removeItemAtPath:home error:NULL];
        [files createDirectoryAtPath:home
         withIntermediateDirectories:YES
                          attributes:nil
                               error:NULL];
        setenv("BELLPAD_DATA_HOME", home.fileSystemRepresentation, 1);
        check(pc_apple_prepare_data_directory() == 1,
              "isolated data directory prepared");

        NSString* chosen = [home stringByAppendingPathComponent:@"placeholder.iso"];
        NSString* moved = [home stringByAppendingPathComponent:@"renamed.iso"];
        [@"placeholder" writeToFile:chosen
                         atomically:YES
                           encoding:NSUTF8StringEncoding
                              error:NULL];

        char resolved[PATH_MAX];

        check(pc_apple_load_disc_path(resolved, sizeof(resolved)) == 0,
              "a fresh data directory remembers nothing");

        check(pc_apple_store_disc_path(chosen.fileSystemRepresentation) == 1,
              "the chosen image is remembered");
        check(pc_apple_load_disc_path(resolved, sizeof(resolved)) == 1 &&
                  same_file_path(resolved, chosen),
              "the remembered image resolves to the same file");

        [files moveItemAtPath:chosen toPath:moved error:NULL];
        check(pc_apple_load_disc_path(resolved, sizeof(resolved)) == 1 &&
                  same_file_path(resolved, moved),
              "a renamed image still resolves");

        [files removeItemAtPath:moved error:NULL];
        check(pc_apple_load_disc_path(resolved, sizeof(resolved)) == 0,
              "a deleted image stops resolving");
        /* An unresolvable reference is deliberately retained: the image may sit
         * on a volume that is only temporarily unmounted. Dropping the stored
         * reference is the caller's decision, made after the core rejects a
         * file that did resolve. */
        check([files fileExistsAtPath:@"disc.alias"],
              "an unresolvable reference is retained, not discarded");

        [@"placeholder" writeToFile:moved
                         atomically:YES
                           encoding:NSUTF8StringEncoding
                              error:NULL];
        check(pc_apple_store_disc_path(moved.fileSystemRepresentation) == 1,
              "a replacement image is remembered");
        pc_apple_forget_disc_path();
        check(pc_apple_load_disc_path(resolved, sizeof(resolved)) == 0,
              "forgetting clears the reference");

        check(pc_apple_store_disc_path(NULL) == 0, "a null path is rejected");
        check(pc_apple_store_disc_path("") == 0, "an empty path is rejected");
        check(pc_apple_load_disc_path(NULL, sizeof(resolved)) == 0,
              "a null output buffer is rejected");
        check(pc_apple_load_disc_path(resolved, 0) == 0,
              "a zero-capacity output buffer is rejected");

        check(pc_apple_store_disc_path(moved.fileSystemRepresentation) == 1,
              "reference restored for the capacity check");
        check(pc_apple_load_disc_path(resolved, 4) == 0,
              "a path longer than the output buffer is rejected");

        if (chdir("/") != 0) {
            check(0, "left the isolated data directory");
        }
        [files removeItemAtPath:home error:NULL];
    }

    printf("%s\n", failures == 0 ? "PC Apple disc-memory tests passed."
                                 : "PC Apple disc-memory tests FAILED.");
    return failures == 0 ? 0 : 1;
}
