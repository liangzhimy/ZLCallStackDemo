//
//  ViewController.m
//  ZLCallStackDemo
//
//  Created by liangzhimy on 2019/8/1.
//  Copyright © 2019 liangzhimy. All rights reserved.
//

#import "ViewController.h"
#import "ZLCallStack.h"

@interface ViewController ()

@property (strong, nonatomic) ZLCallStack *callStack;

@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.callStack = [ZLCallStack new];
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
        NSString *string = [self.callStack stackTraceMainThread];
        NSLog(@"### %@", string);
    });
    [self foo];
}

- (void)foo {
    [self bar];
}

- (void)bar {
    while (true) {
        ;
    }
}

- (void)__callSomething {
    NSLog(@"CALL Something");
    //    [self.callStack start];
}

@end
