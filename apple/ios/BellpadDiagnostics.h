#pragma once
#include <stddef.h>
#ifdef __cplusplus
extern "C" {
#endif
void bellpad_diagnostics_start(void);
void bellpad_log_runtime(int level, const char *category, const char *message, size_t length);
void bellpad_diagnostics_frame(void);
double bellpad_diagnostics_fps(void);
#ifdef __cplusplus
}
#endif
#ifdef __OBJC__
#import <Foundation/Foundation.h>
void BellpadLog(NSString *format, ...) NS_FORMAT_FUNCTION(1, 2);
NSString *BellpadDiagnosticsRedact(NSString *message);
NSURL *BellpadDiagnosticsReport(NSString *summary, NSString *context, NSError **error);
#endif
