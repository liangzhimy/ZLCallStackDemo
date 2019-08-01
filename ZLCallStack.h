//
//  ZLCallStack.h
//  testThreadBacktrace
//
//  Created by liangzhimy on 2019/7/25.
//  Copyright © 2019 liangzhimy. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

#ifdef __LP64__
typedef struct mach_header_64     machHeaderByCPU;
typedef struct segment_command_64 segmentComandByCPU;
typedef struct section_64         sectionByCPU;
typedef struct nlist_64           nlistByCPU;
#define LC_SEGMENT_ARCH_DEPENDENT LC_SEGMENT_64

#else
typedef struct mach_header        machHeaderByCPU;
typedef struct segment_command    segmentComandByCPU;
typedef struct section            sectionByCPU;
typedef struct nlist              nlistByCPU;
#define LC_SEGMENT_ARCH_DEPENDENT LC_SEGMENT
#endif

#ifndef SEG_DATA_CONST
#define SEG_DATA_CONST  "__DATA_CONST"
#endif

@interface ZLCallStack : NSObject

- (NSString *)stackTraceMainThread;
- (NSString *)stackTraceAllThread;
- (NSString *)stackTraceThread:(NSThread *)thread; 

- (void)start;

@end

NS_ASSUME_NONNULL_END
