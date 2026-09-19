// Exercises real disk rotation, concurrent writers, redaction and bounded reports.
#import "../apple/ios/BellpadDiagnostics.mm"
#include <cassert>
#include <thread>
#include <vector>
int main() {
    @autoreleasepool {
        NSString *directory = [NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
        sDirectory = directory; sSession = @"fixture"; sCounts = [NSMutableDictionary dictionary];
        assert([NSFileManager.defaultManager createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:nil]);
        NSString *privateLine = @"failed file:///private/var/mobile/Containers/Data/Application/12345678-1234-1234-1234-123456789abc/private save.gci";
        assert(![BellpadDiagnosticsRedact(privateLine) containsString:@"private save"]);
        assert(![BellpadDiagnosticsRedact(@"me@example.com 12345678-1234-1234-1234-123456789abc") containsString:@"example"]);
        BellpadLog(@"%@", privateLine);
        for (int i = 0; i < 10000; ++i) bellpad_log_runtime(4, "renderer", "same warning", 12);
        assert(sCounts.count == 1 && [sCounts.allValues.firstObject intValue] == 10000);
        for (int i = 0; i < 200; ++i) {
            NSString *m = [NSString stringWithFormat:@"kind %d", i];
            bellpad_log_runtime(2, "fixture", m.UTF8String, strlen(m.UTF8String));
        }
        assert(sCounts.count == 128 && sDropped > 0);
        std::vector<std::thread> writers;
        for (int t = 0; t < 4; ++t) writers.emplace_back([] {
            @autoreleasepool {
                NSString *line = [@"bounded line " stringByPaddingToLength:1000 withString:@"x" startingAtIndex:0];
                for (int i = 0; i < 400; ++i) BPWrite(line);
            }
        });
        for (auto &writer : writers) writer.join();
        for (NSString *name in @[@"current.log", @"current-older.log"]) {
            unsigned long long size = [[NSFileManager.defaultManager attributesOfItemAtPath:[directory stringByAppendingPathComponent:name] error:nil][NSFileSize] unsignedLongLongValue];
            assert(size > 0 && size < kLimit + 8192);
        }
        NSError *error = nil;
        NSURL *url = BellpadDiagnosticsReport(@"fixture me@example.com", @"no private data", &error);
        assert(url && !error);
        NSString *report = [NSString stringWithContentsOfURL:url encoding:NSUTF8StringEncoding error:nil];
        assert([report containsString:@"10000 occurrences"]);
        assert(![report containsString:@"example.com"] && report.length < 1200000);
        assert(![report containsString:@"private save"]);
        NSURL *issue = BellpadDiagnosticsIssueURL(@"Menu & controls?", @"Open menu /private/secret/save.gci", @"Sometimes");
        NSURLComponents *parts = [NSURLComponents componentsWithURL:issue resolvingAgainstBaseURL:NO];
        assert([parts.host isEqualToString:@"github.com"] && [parts.path isEqualToString:@"/chrissotraidis/bellpad/issues/new"]);
        NSMutableDictionary *query = [NSMutableDictionary dictionary];
        for (NSURLQueryItem *item in parts.queryItems) query[item.name] = item.value;
        assert([query[@"title"] isEqualToString:@"[Bug]: Menu & controls?"]);
        assert([query[@"body"] containsString:@"Sometimes"] && [query[@"body"] containsString:@"fixture"]);
        assert(![issue.absoluteString containsString:@"secret"]);
        NSString *large = [@"🎮" stringByPaddingToLength:5000 withString:@"🎮" startingAtIndex:0];
        assert(BellpadDiagnosticsIssueURL(large, large, large).absoluteString.length <= 7500);
        // Disk failure returns an error, never throws through game code.
        sDirectory = [directory stringByAppendingPathComponent:@"missing/child"];
        BellpadLog(@"unwritable log destination");
        assert(!BellpadDiagnosticsReport(@"fixture", @"", &error) && error);
        [NSFileManager.defaultManager removeItemAtPath:directory error:nil];
        puts("Diagnostics: redaction, repeat/unique bounds, concurrent rotation, report and I/O failure passed");
    }
}
