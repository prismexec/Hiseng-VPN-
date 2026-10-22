// Measures how much memory the OpenFlux core takes once loaded, the number
// that matters for the iOS tunnel extension (about 50 MB allowed).
#include <stdio.h>
#include <unistd.h>
#include <mach/mach.h>
#include "liboflux.h"

static double footprint(void) {
    task_vm_info_data_t info;
    mach_msg_type_number_t count = TASK_VM_INFO_COUNT;
    if (task_info(mach_task_self(), TASK_VM_INFO, (task_info_t)&info, &count) != KERN_SUCCESS) return -1;
    return info.phys_footprint / 1048576.0;
}

int main(void) {
    printf("at main (Go runtime loading): %.1f MB\n", footprint());
    char *s = OpenFluxReadLog();   // waits for Go package init
    OpenFluxFreeString(s);
    printf("after Go init: %.1f MB\n", footprint());
    sleep(3);
    printf("after 3 s idle: %.1f MB\n", footprint());
    return 0;
}
