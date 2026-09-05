// Test-only replacement for the read-only WindowServer function. Link this
// object into SpaceTypeBridgeTests, never the Ice target. A requested space ID
// is returned as its native uint32_t type, including unknown future values.
#include <stdint.h>

uint32_t CGSSpaceGetType(int32_t connection, intptr_t space) {
    (void)connection;
    return (uint32_t)space;
}
