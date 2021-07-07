//
//  ORThreadContext.m
//  OCRunner
//
//  Created by Jiang on 2021/6/4.
//

#import "ORThreadContext.h"
#import "MFValue.h"
#import "MFScopeChain.h"
@interface ORCallFrameStack()
@property(nonatomic, strong) NSMutableArray<NSArray *> *array;
@end
@implementation ORCallFrameStack
- (instancetype)init
{
    self = [super init];
    if (self) {
        self.array = [NSMutableArray array];
    }
    return self;
}
+ (void)pushMethodCall:(ORMethodNode *)imp instance:(MFValue *)instance{
    [[ORCallFrameStack threadStack].array addObject:@[instance, imp]];
}
+ (void)pushFunctionCall:(ORFunctionNode *)imp scope:(MFScopeChain *)scope{
    [[ORCallFrameStack threadStack].array addObject:@[scope, imp]];
}
+ (void)pop{
    [[ORCallFrameStack threadStack].array removeLastObject];
}
+ (instancetype)threadStack{
    return ORThreadContext.threadContext.callFrameStack;
}
+ (NSString *)history{
    NSMutableArray *frames = [ORCallFrameStack threadStack].array;
    NSMutableString *log = [@"OCRunner Frames:\n\n" mutableCopy];
    for (int i = 0; i < frames.count; i++) {
        NSArray *frame = frames[i];
        if ([frame.firstObject isKindOfClass:[MFValue class]]) {
            MFValue *instance = frame.firstObject;
            ORMethodNode *imp = frame.lastObject;
            
            [log appendFormat:@"%@ %@ %@\n", imp.declare.isClassMethod ? @"+" : @"-", instance.objectValue, imp.declare.selectorName];
        }else{
            MFScopeChain *scope = frame.firstObject;
            ORFunctionNode *imp = frame.lastObject;
            if (imp.declare.var.varname == nil){
                [log appendFormat:@"Block Call: Captured external variables '%@' \n",[scope.vars.allKeys componentsJoinedByString:@","]];
                // 比如dispatch_after中的block，此时只会孤零零的提醒你一个Block Call
                // 异步调用时，此时通过语法树回溯，可以定位到 block 所在的类以及方法名
                if (i == 0) {
                    ORNode *parent = imp.parentNode;
                    while (parent != nil ) {
                        if ([parent isKindOfClass:[ORClassNode class]]) {
                            [log appendFormat:@"Block Code in Class: %@\n", [(ORClassNode *)parent className]];
                        }else if ([parent isKindOfClass:[ORMethodNode class]]){
                            ORMethodNode *imp = (ORMethodNode *)parent;
                            [log appendFormat:@"Block Code in Method: %@%@\n", imp.declare.isClassMethod ? @"+" : @"-", imp.declare.selectorName];
                        }else if ([parent isKindOfClass:[ORFunctionCall class]]){
                            ORFunctionCall *imp = (ORFunctionCall *)parent;
                            [log appendFormat:@"Block Code in Function call: %@\n", [(ORValueNode *)imp.caller value]];
                        }else if ([parent isKindOfClass:[ORMethodCall class]]){
                            ORMethodCall *imp = (ORMethodCall *)parent;
                            [log appendFormat:@"Block Code in Method call: %@\n", imp.selectorName];
                        }else if ([parent isKindOfClass:[ORInitDeclaratorNode class]]){
                            ORInitDeclaratorNode *imp = (ORInitDeclaratorNode *)parent;
                            [log appendFormat:@"Block Code in Decl: %@ %@\n", imp.declarator.type.name, imp.declarator.var.varname];
                        }
                        parent = parent.parentNode;
                    }
                }
            }else{
                [log appendFormat:@" CFunction: %@\n", imp.declare.var.varname];
            }
        }
    }
    return log;
}
@end

@interface ORArgsStack()
@property(nonatomic, strong) NSMutableArray<NSMutableArray *> *array;
@end
@implementation ORArgsStack
- (instancetype)init{
    if (self = [super init]) {
        _array = [NSMutableArray array];
    }
    return self;
}
+ (instancetype)threadStack{
    return ORThreadContext.threadContext.argsStack;
}
+ (void)push:(NSMutableArray <MFValue *> *)value{
    NSAssert(value, @"value can not be nil");
    [ORArgsStack.threadStack.array addObject:value];
}

+ (NSMutableArray <MFValue *> *)pop{
    NSMutableArray *value = [ORArgsStack.threadStack.array  lastObject];
    NSAssert(value, @"stack is empty");
    [ORArgsStack.threadStack.array removeLastObject];
    return value;
}
+ (BOOL)isEmpty{
    return [ORArgsStack.threadStack.array count] == 0;
}
+ (NSUInteger)size{
    return ORArgsStack.threadStack.array.count;
}
@end

@implementation ORThreadContext

- (void)push:(NSArray *)vars{
    [mem_array addObjectsFromArray:vars];
    cursor += vars.count;
//    for (id object in vars) {
//        void *ptr = (__bridge void *)object;
//        mem[sp + cursor] = ptr;
//        cursor++;
//    }
//    assert(mem + sp + cursor < mem_end);
}
- (id)seek:(mem_cursor)offset{
//    void *ptr = (void *)mem[sp + offset];
//    return (__bridge id)(ptr);
    id result = mem_array[sp + offset];
    NSAssert([result isKindOfClass:[MFValue class]], @"%d", sp + offset);
    return result;
}
- (void)enter{
//    mem[sp] = fp;
    mem_array[sp + cursor] = @(fp);
    fp = sp;
    sp += 1;
    cursor = 0;
}
- (void)exit{
//    sp = mem[fp];
    sp = [mem_array[fp] unsignedIntValue];
    fp = sp - 1;
    cursor = 0;
}
+ (instancetype)threadContext{
    static dispatch_once_t onceToken;
    static ORThreadContext *ctx = nil;
    dispatch_once(&onceToken, ^{
        ctx = [ORThreadContext new];
    });
    return ctx;
    
//    //每一个线程拥有一个独立的上下文
//    NSMutableDictionary *threadInfo = [[NSThread currentThread] threadDictionary];
//    ORThreadContext *ctx = threadInfo[@"ORThreadContext"];
//    if (!ctx) {
//        ctx = [[ORThreadContext alloc] init];
//        threadInfo[@"ORThreadContext"] = ctx;
//    }
//    return ctx;
}
- (instancetype)init
{
    self = [super init];
    if (self) {
        sp = 0;
        fp = 0;
        cursor = 0;
        size_t mem_size = 1024 * 1024;
        mem = malloc(sizeof(UInt64) * mem_size);
        mem_end = mem + mem_size;
        mem_array = [NSMutableArray array];
        self.argsStack = [[ORArgsStack alloc] init];
        self.callFrameStack = [[ORCallFrameStack alloc] init];
    }
    return self;
}
@end