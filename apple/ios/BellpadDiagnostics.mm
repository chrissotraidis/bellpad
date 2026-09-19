#import "BellpadDiagnostics.h"
#import <os/log.h>
#include <atomic>
#include <mutex>
#include <sys/utsname.h>

// Low-frequency breadcrumbs only. No stdout capture, game input, save contents,
// file inventory, device names/identifiers, or automatic network submission.
static std::recursive_mutex sLock;
static NSString *sDirectory;
static NSString *sSession;
static NSMutableDictionary<NSString *, NSNumber *> *sCounts;
static NSUInteger sDropped;
static std::atomic_uint64_t sFrames{0};
static uint64_t sLastFrames;
static NSTimeInterval sLastTime;
static const NSUInteger kLimit = 256 * 1024;

NSString *BellpadDiagnosticsRedact(NSString *message) {
    if (!message) return @"";
    if (message.length > 4096) message = [message substringToIndex:4096];
    NSMutableString *safe = [[message stringByReplacingOccurrencesOfString:NSHomeDirectory()
                                                               withString:@"<app>"] mutableCopy];
    // Paths may contain spaces; discard the remainder of a path-bearing line.
    // This deliberately favors privacy over retaining an entire runtime error.
    for (NSString *pattern in @[@"(?i)(?:file://|https?://|(?<![A-Za-z0-9])/[A-Za-z0-9]|<app>/)[^\\r\\n]*",
                                @"(?i)[A-Z0-9._%+-]+@[A-Z0-9.-]+\\.[A-Z]{2,}",
                                @"(?i)\\b[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\\b"]) {
        NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:pattern options:0 error:nil];
        [regex replaceMatchesInString:safe options:0 range:NSMakeRange(0, safe.length) withTemplate:@"<redacted>"];
    }
    [safe replaceOccurrencesOfString:@"\n" withString:@" " options:0 range:NSMakeRange(0, safe.length)];
    [safe replaceOccurrencesOfString:@"\r" withString:@" " options:0 range:NSMakeRange(0, safe.length)];
    return safe;
}

static void BPWrite(NSString *message) {
    std::lock_guard<std::recursive_mutex> lock(sLock);
    if (!sDirectory) return;
    NSString *path = [sDirectory stringByAppendingPathComponent:@"current.log"];
    NSFileManager *files = NSFileManager.defaultManager;
    if ([[files attributesOfItemAtPath:path error:nil][NSFileSize] unsignedLongLongValue] >= kLimit) {
        NSString *older = [sDirectory stringByAppendingPathComponent:@"current-older.log"];
        [files removeItemAtPath:older error:nil];
        if (![files moveItemAtPath:path toPath:older error:nil]) return;
    }
    NSString *line = [NSString stringWithFormat:@"%.3f session=%@ %@\n", NSDate.date.timeIntervalSince1970, sSession, message];
    NSData *data = [line dataUsingEncoding:NSUTF8StringEncoding];
    if (![files fileExistsAtPath:path]) [files createFileAtPath:path contents:nil attributes:nil];
    // FileHandle errors must never crash the running game (e.g. storage full).
    NSFileHandle *handle = [NSFileHandle fileHandleForWritingAtPath:path];
    NSError *error = nil;
    if (handle && [handle seekToEndReturningOffset:nil error:&error]) [handle writeData:data error:&error];
    [handle closeAndReturnError:nil];
}

void BellpadLog(NSString *format, ...) {
    @autoreleasepool {
        va_list args; va_start(args, format);
        NSString *message = [[NSString alloc] initWithFormat:format arguments:args];
        va_end(args);
        message = BellpadDiagnosticsRedact(message);
        os_log_with_type(OS_LOG_DEFAULT, OS_LOG_TYPE_DEFAULT, "[Bellpad] %{public}s", message.UTF8String);
        BPWrite(message);
    }
}

void bellpad_diagnostics_start(void) {
    std::lock_guard<std::recursive_mutex> lock(sLock);
    if (sDirectory) return;
    NSURL *support = [NSFileManager.defaultManager URLsForDirectory:NSApplicationSupportDirectory inDomains:NSUserDomainMask].firstObject;
    sDirectory = [[support URLByAppendingPathComponent:@"Bellpad/Diagnostics" isDirectory:YES] path];
    [NSFileManager.defaultManager createDirectoryAtPath:sDirectory withIntermediateDirectories:YES attributes:nil error:nil];
    for (NSString *part in @[@"", @"-older"]) {
        NSString *old = [sDirectory stringByAppendingPathComponent:[NSString stringWithFormat:@"previous%@.log", part]];
        [NSFileManager.defaultManager removeItemAtPath:old error:nil];
        [NSFileManager.defaultManager moveItemAtPath:[sDirectory stringByAppendingPathComponent:[NSString stringWithFormat:@"current%@.log", part]] toPath:old error:nil];
    }
    sSession = [NSUUID.UUID.UUIDString substringToIndex:8];
    sCounts = [NSMutableDictionary dictionary];
    struct utsname hardware; uname(&hardware);
    NSBundle *bundle = NSBundle.mainBundle;
    BellpadLog(@"session start version=%@ build=%@ hardware=%s os=%@", [bundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"] ?: @"unknown", [bundle objectForInfoDictionaryKey:@"CFBundleVersion"] ?: @"unknown", hardware.machine, NSProcessInfo.processInfo.operatingSystemVersionString);
    NSURL *provenanceURL = [bundle URLForResource:@"SourceProvenance" withExtension:@"json"];
    NSData *provenanceData = provenanceURL ? [NSData dataWithContentsOfURL:provenanceURL] : nil;
    NSDictionary *provenance = provenanceData ? [NSJSONSerialization JSONObjectWithData:provenanceData options:0 error:nil] : nil;
    BellpadLog(@"source commit=%@ executable=%@ toolchain=%@", provenance[@"appCommit"] ?: @"unknown", provenance[@"executableSha256"] ?: @"unknown", provenance[@"xcode"] ?: @"unknown");
    for (NSDictionary *component in provenance[@"sources"][@"components"])
        BellpadLog(@"component=%@ pin=%@", component[@"name"], component[@"commit"]);
}

void bellpad_log_runtime(int level, const char *category, const char *message, size_t length) {
    @autoreleasepool {
        NSString *text = [[NSString alloc] initWithBytes:message ?: "" length:message ? MIN(length, (size_t)4096) : 0 encoding:NSUTF8StringEncoding] ?: @"<non-UTF8 runtime event>";
        NSString *key = BellpadDiagnosticsRedact([NSString stringWithFormat:@"runtime level=%d category=%s %@", level, category ?: "unknown", text]);
        std::lock_guard<std::recursive_mutex> lock(sLock);
        if (!sCounts) return;
        NSUInteger count = [sCounts[key] unsignedIntegerValue] + 1;
        if (!sCounts[key] && sCounts.count >= 128) {
            ++sDropped;
            // Preserve a sample of new errors even after noisy informational
            // categories have filled the summary. Fatal messages always survive.
            if (level >= 4 || (level >= 3 && (sDropped <= 10 || sDropped % 1000 == 0)))
                BellpadLog(@"%@ summary-capacity-reached suppressed=%lu", key, (unsigned long)sDropped);
            return;
        }
        sCounts[key] = @(count);
        if (count == 1 || count == 10 || count == 100 || count % 1000 == 0)
            BellpadLog(@"%@ repeats=%lu", key, (unsigned long)count);
    }
}

void bellpad_diagnostics_frame(void) { ++sFrames; }
double bellpad_diagnostics_fps(void) {
    std::lock_guard<std::recursive_mutex> lock(sLock);
    NSTimeInterval now = NSProcessInfo.processInfo.systemUptime;
    uint64_t frames = sFrames.load();
    double fps = sLastTime > 0 && now > sLastTime ? (frames - sLastFrames) / (now - sLastTime) : 0;
    sLastTime = now; sLastFrames = frames;
    return fps;
}

NSURL *BellpadDiagnosticsReport(NSString *summary, NSString *context, NSError **error) {
    std::lock_guard<std::recursive_mutex> lock(sLock);
    if (!sDirectory) bellpad_diagnostics_start();
    NSMutableString *report = [NSMutableString stringWithFormat:@"Bellpad diagnostic report — schema 1\nSession: %@\nSummary: %@\nContext: %@\n\nLogs exclude game/save data, controller inputs, device identifiers and signing material. Review your own description before sharing. No automatic upload.\n", sSession, BellpadDiagnosticsRedact(summary), BellpadDiagnosticsRedact(context)];
    NSArray *keys = [[sCounts allKeys] sortedArrayUsingSelector:@selector(compare:)];
    for (NSString *key in keys) [report appendFormat:@"%@: %@ occurrences\n", key, sCounts[key]];
    [report appendFormat:@"Additional event kinds suppressed: %lu\n", (unsigned long)sDropped];
    for (NSString *name in @[@"previous-older.log", @"previous.log", @"current-older.log", @"current.log"]) {
        NSData *data = [NSData dataWithContentsOfFile:[sDirectory stringByAppendingPathComponent:name]];
        if (data.length > kLimit + 8192) data = [data subdataWithRange:NSMakeRange(data.length - kLimit, kLimit)];
        [report appendFormat:@"\n--- %@ ---\n%@", name, [[NSString alloc] initWithData:data ?: [NSData data] encoding:NSUTF8StringEncoding] ?: @"<unreadable log>\n"];
    }
    NSURL *url = [NSURL fileURLWithPath:[sDirectory stringByAppendingPathComponent:@"Bellpad-Diagnostics.txt"]];
    return [report writeToURL:url atomically:YES encoding:NSUTF8StringEncoding error:error] ? url : nil;
}
