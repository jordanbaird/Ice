//
//  CGSSpace.h
//  Bridging
//

#ifndef CGS_SPACE_INTERNAL_H
#define CGS_SPACE_INTERNAL_H

#include "CGSConnection.h"

typedef size_t CGSSpaceID;

typedef enum {
    kCGSSpaceIncludesCurrent = 1 << 0,
    kCGSSpaceIncludesOthers = 1 << 1,
    kCGSSpaceIncludesUser = 1 << 2,

    kCGSSpaceVisible = 1 << 16,

    kCGSCurrentSpaceMask = kCGSSpaceIncludesUser | kCGSSpaceIncludesCurrent,
    kCGSOtherSpacesMask = kCGSSpaceIncludesOthers | kCGSSpaceIncludesCurrent,
    kCGSAllSpacesMask = kCGSSpaceIncludesUser | kCGSSpaceIncludesOthers | kCGSSpaceIncludesCurrent,
    kCGSAllVisibleSpacesMask = kCGSSpaceVisible | kCGSAllSpacesMask,
} CGSSpaceMask;

CG_EXTERN CGSSpaceID CGSGetActiveSpace(CGSConnectionID cid);

CG_EXTERN CFArrayRef CGSCopySpacesForWindows(CGSConnectionID cid, CGSSpaceMask mask, CFArrayRef windowIDs);

#endif /* CGS_SPACE_INTERNAL_H */
