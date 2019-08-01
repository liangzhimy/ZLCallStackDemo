//
//  ZLCallStack.m
//  testThreadBacktrace
//
//  Created by liangzhimy on 2019/7/25.
//  Copyright © 2019 liangzhimy. All rights reserved.
//

#import "ZLCallStack.h"
#include <mach/mach.h>
#include <dlfcn.h>
#include <pthread.h>
#include <mach-o/dyld.h>
#include <mach-o/loader.h>
#include <mach-o/nlist.h>

#include <mach/task.h>
#include <mach/vm_map.h>
#include <mach/mach_init.h>
#include <mach/thread_act.h>
#include <mach/thread_info.h>

#include <string.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stddef.h>
#include <stdint.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <sys/time.h>
#include <sys/sysctl.h>
#include <objc/message.h>
#include <objc/runtime.h>
#include <dispatch/dispatch.h>
#include <mach/machine/kern_return.h>

#import <mach/mach.h>
#include <dlfcn.h>
#include <pthread.h>
#include <sys/types.h>
#include <limits.h>
#include <string.h>
#include <mach-o/dyld.h>
#include <mach-o/nlist.h>

#if defined(__LP64__)
#define TRACE_FMT         "%-4d%-31s 0x%016lx %s + %lu"
#define POINTER_FMT       "0x%016lx"
#define POINTER_SHORT_FMT "0x%lx"
#define BS_NLIST struct nlist_64
#else
#define TRACE_FMT         "%-4d%-31s 0x%08lx %s + %lu"
#define POINTER_FMT       "0x%08lx"
#define POINTER_SHORT_FMT "0x%lx"
#define BS_NLIST struct nlist
#endif

static thread_act_array_t g_suspendedThreads = NULL;
static mach_msg_type_number_t g_suspendedThreadsCount = 0;

typedef struct MKStackFrame {
    struct MKStackFrame *previous;
    uintptr_t return_address;
} MKStackFrame;

@interface ZLCallStack () {
    thread_t main_thread;
}

@property (strong, nonatomic) NSThread *thread;

@end

static mach_port_t _mainThreadId;

@implementation ZLCallStack

+ (void)load {
    _mainThreadId = mach_thread_self();
}

- (NSString *)stackTraceMainThread {
    return __stackOfMainThread();
}

- (NSString *)stackTraceAllThread {
    return __stackOfAllThread();
}

- (NSString *)stackTraceThread:(NSThread *)thread {
    return __stackOfNSThread(thread);
}

- (void)start {
    NSLog(@"start");
    dispatch_async(dispatch_get_global_queue(0, 0), ^{
        __stackOfMainThread();
    });
//    self.thread = [[NSThread alloc] initWithTarget:self selector:@selector(__threadStart) object:nil];
//    [self.thread start];
}

thread_t __thread_self() {
    thread_t thread_self = mach_thread_self();
    mach_port_deallocate(mach_task_self(), thread_self);
    return thread_self;
}

- (void)__threadStart {
    __suspendThread();
    __stackOfMainThread(); 
//    __stackOfAllThread();
}

static void __suspendThread() {
    kern_return_t kr;
    const task_t thisTask = mach_task_self();
    if((kr = task_threads(thisTask, &g_suspendedThreads, &g_suspendedThreadsCount)) != KERN_SUCCESS) {
        printf("task_threads: %s", mach_error_string(kr));
        return;
    }
    
    const thread_t thisThread = (thread_t)__thread_self();
    
    for(mach_msg_type_number_t i = 0; i < g_suspendedThreadsCount; i++) {
        thread_t thread = g_suspendedThreads[i];
        if(thread != thisThread) {
            if((kr = thread_suspend(thread)) != KERN_SUCCESS) {
                // Record the error and keep going.
                printf("thread_suspend (%08x): %s", thread, mach_error_string(kr));
            }
        }
    }
}

static void __getThreadState(thread_t thread, _STRUCT_MCONTEXT *ctx) {
#if defined(__x86_64__)
    mach_msg_type_number_t count = x86_THREAD_STATE64_COUNT;
    thread_get_state(thread, x86_THREAD_STATE64, (thread_state_t)&ctx->__ss, &count);
#elif defined(__arm64__)
    mach_msg_type_number_t count = ARM_THREAD_STATE64_COUNT;
    thread_get_state(thread, ARM_THREAD_STATE64, (thread_state_t)&ctx.__ss, &count);
#endif
}

NSString *__stackOfAllThread() {
    thread_act_array_t threads;
    mach_msg_type_number_t thread_count = 0;
    const task_t this_task = mach_task_self();
    kern_return_t kr = task_threads(this_task, &threads, &thread_count);
    if (kr != KERN_SUCCESS) {
        return @"fail get all threads";
    }
    NSMutableString *reStr = [NSMutableString stringWithFormat:@"Call %u thread:\n", thread_count];
    for (int i = 0; i < thread_count; i++) {
        NSString *str = __stackOfThread(threads[i]);
        if (![str length]) {
            continue;
        }
        [reStr appendString:__stackOfThread(threads[i])];
    }
    return [reStr copy];
}

NSString *__stackOfNSThread(NSThread *thread) {
    return __stackOfThread(__machThreadFromNSThread([NSThread mainThread]));
}

NSString *__stackOfMainThread() {
    return __stackOfNSThread([NSThread mainThread]);
}

NSString *__stackOfCurrentThread() {
    return __stackOfThread(mach_thread_self());
}

thread_t __machThreadFromNSThread(NSThread *nsthread) {
    char name[256];
    mach_msg_type_number_t count;
    thread_act_array_t list;
    task_threads(mach_task_self(), &list, &count);
    
    NSTimeInterval currentTimestamp = [[NSDate date] timeIntervalSince1970];
    NSString *originName = [nsthread name];
    [nsthread setName:[NSString stringWithFormat:@"%f", currentTimestamp]];
    
    if ([nsthread isMainThread]) {
        return (thread_t)_mainThreadId;
    }
    
    for (int i = 0; i < count; i++) {
        pthread_t pt = pthread_from_mach_thread_np(list[i]);
        if ([nsthread isMainThread]) {
            if (list[i] == _mainThreadId) {
                return list[i];
            }
        }
        if (pt) {
            name[0] = '\0';
            pthread_getname_np(pt, name, sizeof name);
            if (!strcmp(name, [nsthread name].UTF8String)) {
                [nsthread setName:originName];
                return list[i];
            }
        }
    }
    
    [nsthread setName:originName];
    return mach_thread_self();
}

NSString *__stackOfThread(thread_t thread) {
    _STRUCT_MCONTEXT ctx;
    __getThreadState(thread, &ctx);
#if defined(__x86_64__)
    uint64_t pc = ctx.__ss.__rip;
    uint64_t sp = ctx.__ss.__rsp;
    uint64_t fp = ctx.__ss.__rbp;
#elif defined(__arm64__)
    uint64_t pc = ctx.__ss.__pc;
    uint64_t sp = ctx.__ss.__sp;
    uint64_t fp = ctx.__ss.__fp;
#endif
    NSMutableString *resultString = [[NSMutableString alloc] initWithFormat:@"Backtrace of Thread %u:\n", thread];

    uintptr_t buffer[100];
    int i = 0;
    buffer[i] = pc;
    i++;
    
    if (pc == 0) {
        return @"Fail to get instruction address";
    }
    
    MKStackFrame stackFrame = {0};
    vm_size_t bytesCopied = 0;
    if (fp == 0 || vm_read_overwrite(mach_task_self(),
                                     (vm_address_t)(fp),
                                     sizeof(stackFrame),
                                     (vm_address_t)&stackFrame,
                                     &bytesCopied) != KERN_SUCCESS) {
        return @"Fail frame pointer";
    }
    
    for (; i < 32; i++) {
        buffer[i] = stackFrame.return_address;
        vm_size_t bytesCopied = 0;
        if (buffer[i] == 0 ||
            stackFrame.previous == 0 ||
            vm_read_overwrite(mach_task_self(),
                              (vm_address_t)(stackFrame.previous),
                              sizeof(stackFrame),
                              (vm_address_t)&stackFrame,
                              &bytesCopied) != KERN_SUCCESS)
            break;
    }
    
    int stackLength = i;
    Dl_info symbolicated[stackLength];
    __symbolicate(buffer, symbolicated, stackLength, 0);
    
    for (int i = 0; i < stackLength; i++) {
        [resultString appendFormat:@"%@", __logBacktraceEntry(i, buffer[i], &symbolicated[i])];
    }
    
    [resultString appendString:@"\n"];
    return resultString;
}

NSString *__logBacktraceEntry(const int entryNum, const uintptr_t address, const Dl_info *const dlInfo) {
    char faddrBuff[20];
    char saddrBuff[20];
    
    const char *fname = __lastPathEntry(dlInfo->dli_fname);
    if (fname == NULL) {
        sprintf(faddrBuff, POINTER_FMT, (uintptr_t)dlInfo->dli_fbase);
        fname = faddrBuff;
    }
    
    uintptr_t offset = address - (uintptr_t)dlInfo->dli_saddr;
    const char *sname = dlInfo->dli_sname;
    if (sname == NULL) {
        sprintf(saddrBuff, POINTER_SHORT_FMT, (uintptr_t)dlInfo->dli_fbase);
        sname = saddrBuff;
        offset = address - (uintptr_t)dlInfo->dli_fbase;
    }
    return [NSString stringWithFormat:@"%-30s   0x%08lx %s + %u\n", fname, (uintptr_t)address, sname, offset];
}

const char *__lastPathEntry(const char* const path) {
    if (path == NULL) {
        return NULL;
    }
    if (strlen(path) == 0) {
        return NULL;
    }
    char *lastFile = strrchr((char *)path, '/');
    return lastFile == NULL ? path : lastFile + 1;
}

void __symbolicate(const uintptr_t* const buffer,
                      Dl_info* const symbolicated,
                      const int stackLength,
                      const int skippedEntries) {
    int i = 0;
    if (!skippedEntries && i < stackLength) {
        __dlAddr(buffer[i], &symbolicated[i]);
        i++;
    }
    for (; i < stackLength; i++) {
        __dlAddr(__instructionAddressByCPU(buffer[i]), &symbolicated[i]);
    }
}

uintptr_t __instructionAddressByCPU(const uintptr_t address) {
#if defined(__arm64__)
    const uintptr_t reAddress = ((address) & ~(3UL));
#elif defined(__arm__)
    const uintptr_t reAddress = ((address) & ~(1UL));
#elif defined(__x86_64__)
    const uintptr_t reAddress = (address);
#elif defined(__i386__)
    const uintptr_t reAddress = (address);
#endif
    return reAddress - 1;
}

bool __dlAddr(const uintptr_t address, Dl_info* const info) {
    info->dli_fname = NULL;
    info->dli_fbase = NULL;
    info->dli_sname = NULL;
    info->dli_saddr = NULL;
    
    const uint32_t imageIndex = __dyldImageIndexFromAddress(address);
    if (imageIndex == UINT_MAX) {
        return false;
    }
    
    /*
     Header
     ------------------
     Load commands
     Segment command 1 -------------|
     Segment command 2              |
     ------------------             |
     Data                           |
     Section 1 data |segment 1 <----|
     Section 2 data |          <----|
     Section 3 data |          <----|
     Section 4 data |segment 2
     Section 5 data |
     ...            |
     Section n data |
     */
    /*----------Mach Header---------*/
    
    const struct mach_header *machHeader = _dyld_get_image_header(imageIndex);
    
    const uintptr_t imageVMAddressSlide = (uintptr_t)_dyld_get_image_vmaddr_slide(imageIndex);
    const uintptr_t addressWithSlide = address - imageVMAddressSlide;
    
    // 得到段的基地址
    const uintptr_t segmentBase = __segmentBaseOfImageIndex(imageIndex) + imageVMAddressSlide;
    if (segmentBase == 0) {
        return false;
    }
    
    info->dli_fname = _dyld_get_image_name(imageIndex);
    info->dli_fbase = (void *)machHeader;
    
    const nlistByCPU *bestMatch = NULL;
    uintptr_t bestDistance = ULONG_MAX;
    uintptr_t cmdPointer = __cmdFirstPointerFromMachHeader(machHeader);
    if (cmdPointer == 0) {
        return false;
    }
    
    for (uint32_t iCmd = 0; iCmd < machHeader->ncmds; iCmd++) {
        const struct load_command *loadCmd = (struct load_command *)cmdPointer;
        if (loadCmd->cmd == LC_SYMTAB) {
            const struct symtab_command *symtabCmd = (struct symtab_command *)cmdPointer;
            const nlistByCPU *symbolTable = (nlistByCPU *)(segmentBase + symtabCmd->symoff);
            const uintptr_t stringTable = segmentBase + symtabCmd->stroff;
            
            for (uint32_t iSym = 0; iSym < symtabCmd->nsyms; iSym++) {
                if (symbolTable[iSym].n_value != 0) {
                    uintptr_t symbolBase = symbolTable[iSym].n_value;
                    uintptr_t currentDistance = addressWithSlide - symbolBase;
                    if ((addressWithSlide >= symbolBase) && (currentDistance <= bestDistance)) {
                        bestMatch = symbolTable + iSym;
                        bestDistance = currentDistance;
                    }
                }
            }
            
            if (bestMatch != NULL) {
                info->dli_saddr = (void *)(bestMatch->n_value + imageVMAddressSlide);
                info->dli_sname = (char *)((intptr_t)stringTable + (intptr_t)bestMatch->n_un.n_strx);
                if (*info->dli_sname == '_') {
                    info->dli_sname++;
                }
                if (info->dli_saddr == info->dli_fbase && bestMatch->n_type == 3) {
                    info->dli_sname = NULL;
                }
                break;
            }
        }
        cmdPointer += loadCmd->cmdsize;
    }
    return false;
}

uintptr_t __segmentBaseOfImageIndex(int imageIndex) {
    const struct mach_header *machHeader = _dyld_get_image_header(imageIndex);
    uintptr_t cmdPtr = __cmdFirstPointerFromMachHeader(machHeader);
    if (cmdPtr == 0) {
        return 0;
    }
    for (uint32_t i = 0; i < machHeader->ncmds; i++) {
        const struct load_command *loadCmd = (struct load_command *)cmdPtr;
        const segmentComandByCPU *segmentCmd = (segmentComandByCPU *)cmdPtr;
        if (strcmp(segmentCmd->segname, SEG_LINKEDIT) == 0) {
            return (uintptr_t)(segmentCmd->vmaddr - segmentCmd->fileoff);
        }
        cmdPtr += loadCmd->cmdsize;
    }
    
    return 0;
}

// 通过address找到对应的image的游标, 从面能得到image的更多的信息
uint32_t __dyldImageIndexFromAddress(const uintptr_t address) {
    const uint32_t imageCount = _dyld_image_count();
    const struct mach_header *machHeader = 0;
    
    for (uint32_t imageIndex = 0; imageIndex < imageCount; imageIndex++) {
        machHeader = _dyld_get_image_header(imageIndex);
        if (machHeader == NULL) {
            continue;
        }
        
        uintptr_t addressWSLide = address - (uintptr_t)_dyld_get_image_vmaddr_slide(imageIndex);
        uintptr_t cmdPointer = __cmdFirstPointerFromMachHeader(machHeader);
        if (cmdPointer == 0) {
            continue;
        }
        
        for (uint32_t cmdIndex = 0; cmdIndex < machHeader->ncmds; cmdIndex++) {
            const struct load_command *loadCmd = (struct load_command*)cmdPointer;
            if (loadCmd->cmd == LC_SEGMENT) {
                const struct segment_command *segCmd = (struct segment_command *)cmdPointer;
                if (addressWSLide >= segCmd->vmaddr && addressWSLide < segCmd->vmaddr + segCmd->vmsize) {
                    return imageIndex;
                }
            } else if (loadCmd->cmd == LC_SEGMENT_64) {
                const struct segment_command_64 *segCmd = (struct segment_command_64 *)cmdPointer;
                if (addressWSLide >= segCmd->vmaddr && addressWSLide < segCmd->vmaddr + segCmd->vmsize) {
                    return imageIndex;
                }
            }
            cmdPointer += loadCmd->cmdsize;
        }
    }
    return UINT_MAX;
}

uintptr_t __cmdFirstPointerFromMachHeader(const struct mach_header* const machHeader) {
    switch (machHeader->magic) {
        case MH_MAGIC:
        case MH_CIGAM:
        case MH_MAGIC_64:
        case MH_CIGAM_64:
            return (uintptr_t)(((machHeaderByCPU*)machHeader) + 1);
        default:
            return 0; // Header 不合法
    }
}

@end
