//
//  CGSWindow.h
//  Bridging
//

#ifndef CGS_WINDOW_INTERNAL_H
#define CGS_WINDOW_INTERNAL_H

#include "CGSConnection.h"

CG_EXTERN CGError CGSGetWindowList(CGSConnectionID cid, CGSConnectionID targetCID, int count, CGWindowID *list, int *outCount);

CG_EXTERN CGError CGSGetOnScreenWindowList(CGSConnectionID cid, CGSConnectionID targetCID, int count, CGWindowID *list, int *outCount);

CG_EXTERN CGError CGSGetProcessMenuBarWindowList(CGSConnectionID cid, CGSConnectionID targetCID, int count, CGWindowID *list, int *outCount);

CG_EXTERN CGError CGSGetWindowCount(CGSConnectionID cid, CGSConnectionID targetCID, int *outCount);

CG_EXTERN CGError CGSGetOnScreenWindowCount(CGSConnectionID cid, CGSConnectionID targetCID, int *outCount);

CG_EXTERN CGError CGSGetScreenRectForWindow(CGSConnectionID cid, CGWindowID wid, CGRect *outRect);

#endif /* CGS_WINDOW_INTERNAL_H */
