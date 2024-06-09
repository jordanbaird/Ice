//
//  CGSConnection.h
//  Bridging
//

#ifndef CGS_CONNECTION_INTERNAL_H
#define CGS_CONNECTION_INTERNAL_H

typedef int CGSConnectionID;

CG_EXTERN CGSConnectionID CGSMainConnectionID(void);

CG_EXTERN CGError CGSCopyConnectionProperty(CGSConnectionID cid, CGSConnectionID targetCID, CFStringRef key, CFTypeRef *outValue);

CG_EXTERN CGError CGSSetConnectionProperty(CGSConnectionID cid, CGSConnectionID targetCID, CFStringRef key, CFTypeRef value);

#endif /* CGS_CONNECTION_INTERNAL_H */
