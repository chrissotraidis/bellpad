#include <assert.h>
#include <stdint.h>
#include <stdio.h>

#include "pc_rtc_clock.h"

static int64_t seconds_to_ticks(int64_t seconds) {
    return seconds * PC_RTC_TIMER_CLOCK;
}

int main(void) {
    assert(pc_rtc_host_ticks(PC_RTC_UNIX_EPOCH_DIFF, 0,
                             -1, -1, -1, 0, 0, 0) == 0);
    assert(pc_rtc_host_ticks(PC_RTC_UNIX_EPOCH_DIFF + 3661, -5 * 60 * 60,
                             -1, -1, -1, 20, 1, 1) == seconds_to_ticks(3661 - 5 * 60 * 60));

    const int64_t ten_twenty_thirty =
        PC_RTC_UNIX_EPOCH_DIFF + 10 * 60 * 60 + 20 * 60 + 30;
    assert(pc_rtc_host_ticks(ten_twenty_thirty, 0,
                             12, 34, 56, 10, 20, 30) ==
           seconds_to_ticks(12 * 60 * 60 + 34 * 60 + 56));
    assert(pc_rtc_host_ticks(ten_twenty_thirty, 0,
                             12, -1, -1, 10, 20, 30) ==
           seconds_to_ticks(12 * 60 * 60 + 20 * 60 + 30));

    assert(pc_rtc_counter_ticks(150, 100) == PC_RTC_TIMER_CLOCK + PC_RTC_TIMER_CLOCK / 2);
    assert(pc_rtc_counter_ticks(UINT64_C(1000000000000), UINT64_C(1000000000)) ==
           seconds_to_ticks(1000));
    assert(pc_rtc_counter_ticks(1234, 0) == 0);
    assert(pc_rtc_subsecond_ticks(500000000) == PC_RTC_TIMER_CLOCK / 2);
    assert(pc_rtc_subsecond_ticks(123456789) ==
           INT64_C(123456789) * PC_RTC_TIMER_CLOCK / INT64_C(1000000000));

    puts("PC RTC clock tests passed");
    return 0;
}
