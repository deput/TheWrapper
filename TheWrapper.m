//
//  TheWrapper.m
//
//  Created by Tomer Shiri on 1/10/13.
//  Modified by deput on 9/9/15
//  Copyright (c) 2013 Tomer Shiri. All rights reserved.
//

#import "TheWrapper.h"
#import <objc/runtime.h>
#import <objc/message.h>

#define BLOCK_SAFE_RUN(block,...) block? block(__VA_ARGS__) : nil;
#define va_list_arg(__name) id __name = va_arg(args, id);

// Hash combining method from http://www.mikeash.com/pyblog/friday-qa-2010-06-18-implementing-equality-and-hashing.html
#define NSUINT_BIT (CHAR_BIT * sizeof(NSUInteger))
#define NSUINTROTATE(val, howmuch) ((((NSUInteger)val) << howmuch) | (((NSUInteger)val) >> (NSUINT_BIT - howmuch)))

static id WrapperFunction(id zelf, SEL _cmd, ...);
@interface WrappedFunctionData : NSObject

@property (nonatomic, copy) void (^preRunBlock)(id<NSObject> zelf, NSArray* args);
@property (nonatomic, copy) id (^postRunBlock)(id<NSObject> zelf, id returnValue, NSArray* args);
@property (nonatomic, assign) IMP originalImplementation;
@property (nonatomic, assign) Method originalMethod;
@end

@implementation WrappedFunctionData {
    void (^_preRunBlock)(id<NSObject> zelf, NSArray* args);
    id (^_postRunBlock)(id<NSObject> zelf, id returnValue, NSArray* args);
    IMP _originalImplementation;
    Method _originalMethod;
}

@synthesize preRunBlock = _preRunBlock, postRunBlock = _postRunBlock, originalImplementation = _originalImplementation;

-(id) initWithOriginalImplementation:(IMP) originalImplementation andPreRunBlock:(void (^)(id<NSObject> zelf,NSArray* args)) preRunblock andPostRunBlock:(id (^)(id<NSObject> zelf, id functionReturnValue, NSArray* args)) postRunBlock {
    self = [super init];
    if (!self) return self;
    self.originalImplementation = originalImplementation;
    self.preRunBlock = preRunblock;
    self.postRunBlock = postRunBlock;
    
    return self;
}

@end

@implementation TheWrapper

static NSMutableDictionary* _wrappedFunctions;

+(id) init {
    return nil;
}

+(void)initialize {
    _wrappedFunctions = [[NSMutableDictionary alloc] init];
}

+(BOOL) isInstance:(id) object {
    return class_isMetaClass(object_getClass(object));
}

+(void) addWrappertoClass:(Class) clazz andSelector:(SEL) selector withPreRunBlock:(void (^)(id<NSObject> zelf,NSArray* args)) preRunblock {
    [TheWrapper addWrappertoClass:clazz andSelector:selector withPreRunBlock:preRunblock andPostRunBlock:nil];
}

+(void) addWrappertoClass:(Class) clazz andSelector:(SEL) selector withPostRunBlock:(id (^)(id<NSObject> zelf, id functionReturnValue,NSArray* args)) postRunBlock {
    [TheWrapper addWrappertoClass:clazz andSelector:selector withPreRunBlock:nil andPostRunBlock:postRunBlock];
}

+(void) addWrappertoClass:(Class) clazz andSelector:(SEL) selector withPreRunBlock:(void (^)(id<NSObject> zelf, NSArray* args)) preRunblock andPostRunBlock:(id (^)(id<NSObject> zelf, id functionReturnValue, NSArray* args)) postRunBlock {
    
    Method originalMethod = class_getInstanceMethod(clazz, selector);
    
    if(originalMethod == nil) {
        originalMethod = class_getClassMethod(clazz, selector);
    }
    
    IMP originaImplementation = method_getImplementation(originalMethod);
    
    WrappedFunctionData* wrappedFunctionData = [_wrappedFunctions objectForKey:[TheWrapper getStoredKeyForClass:clazz andSelector:selector]];
    
    BOOL isAlreadyWrapped = wrappedFunctionData != nil;
    
    if(isAlreadyWrapped) {
        wrappedFunctionData.preRunBlock = preRunblock;
        wrappedFunctionData.postRunBlock = postRunBlock;
    }
    else {
        wrappedFunctionData = [[WrappedFunctionData alloc] initWithOriginalImplementation:originaImplementation andPreRunBlock:preRunblock andPostRunBlock:postRunBlock];
        [_wrappedFunctions setObject:wrappedFunctionData forKey:[TheWrapper getStoredKeyForClass:clazz andSelector:selector]];
    }
    
    if(class_addMethod(clazz, selector, (IMP)WrapperFunction, method_getTypeEncoding(originalMethod))) {
        method_setImplementation(originalMethod, (IMP)WrapperFunction);
    }else {
        class_replaceMethod(clazz, selector, (IMP)WrapperFunction, method_getTypeEncoding(originalMethod));
    }
    
    SEL newSelector = NSSelectorFromString([@"_wrapper_" stringByAppendingString:NSStringFromSelector(selector)]);
    class_addMethod(clazz, newSelector, (IMP)originaImplementation, method_getTypeEncoding(originalMethod));

}

+(void) removeWrapperFrom:(id<NSObject>) target andSelector:(SEL) selector {
    Class clazz = [TheWrapper isInstance:target] ? [target class] : target;
    [TheWrapper removeWrapperFromClass:clazz andSelector:selector];
}

+(void) removeWrapperFromClass:(Class) clazz andSelector:(SEL) selector {
    [TheWrapper addWrappertoClass:clazz andSelector:selector withPreRunBlock:nil andPostRunBlock:nil];
}

+ (NSNumber*)getStoredKeyForClass:(Class)clazz andSelector:(SEL)selector
{
    NSUInteger hash = NSUINTROTATE([clazz hash], NSUINT_BIT / 2) ^ (NSUInteger)((void*)selector);
    return [NSNumber numberWithUnsignedInteger:hash];
}

+ (WrappedFunctionData*) getFunctionData:(Class) clazz andSelector:(SEL) selector
{
    while(clazz)
    {
        WrappedFunctionData* wrappedFunctionData = [_wrappedFunctions objectForKey:[TheWrapper getStoredKeyForClass:clazz andSelector:selector]];
        if (wrappedFunctionData) return wrappedFunctionData;
        clazz = class_getSuperclass(clazz);
    }
    return nil;
}
@end

id WrapperFunction(id zelf, SEL _cmd, ...)
{
    id returnValue = nil;
    @autoreleasepool {
        va_list args;
        va_start(args, _cmd);
        
        WrappedFunctionData* wrappedFunctionData = [TheWrapper getFunctionData:[zelf class] andSelector:_cmd];
        
        if (!wrappedFunctionData) {
            [(NSObject*)zelf doesNotRecognizeSelector:_cmd];
            return zelf;
        }
        
        
        SEL newSelector = NSSelectorFromString([@"_wrapper_" stringByAppendingString:NSStringFromSelector(_cmd)]);
        NSInvocation* invocation = [NSInvocation invocationWithMethodSignature:[[zelf class] instanceMethodSignatureForSelector:newSelector]];
        invocation.selector = newSelector;
        NSUInteger argsCount = invocation.methodSignature.numberOfArguments - 2;
        
        
        NSMutableArray* argsArray = [@[] mutableCopy];
        for(NSUInteger i = 0; i < argsCount ; ++i){
            id arg = va_arg(args,id);
            [argsArray addObject:arg];
        }
        
        //before run
        BLOCK_SAFE_RUN(wrappedFunctionData.preRunBlock, zelf, [argsArray copy]);
        
        
        for(NSUInteger i = 0; i < argsCount ; ++i){
            id obj = [argsArray objectAtIndex:i];
            [invocation setArgument:&obj atIndex:i + 2];
        }
        
        //original IMP
        [invocation invokeWithTarget:zelf];
        
        //has return value
        if (invocation.methodSignature.methodReturnLength) {
            void *tempResultSet;
            [invocation getReturnValue:&tempResultSet];
            returnValue = (__bridge id)tempResultSet;
        }

        //after run
        if (wrappedFunctionData.postRunBlock != nil) {
            returnValue = BLOCK_SAFE_RUN(wrappedFunctionData.postRunBlock, zelf, returnValue, [argsArray copy]);
        }
        va_end(args);
    }
    return returnValue;
}
