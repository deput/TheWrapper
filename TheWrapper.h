//
//  TheWrapper.h
//
//  Created by Tomer Shiri on 1/10/13.
//  Modified by deput on 9/9/15
//  Copyright (c) 2013 Tomer Shiri. All rights reserved.
//
#import <Foundation/Foundation.h>

@interface TheWrapper : NSObject

+(void) addWrappertoClass:(Class) clazz andSelector:(SEL) selector withPreRunBlock:(void (^)(id<NSObject> zelf,NSArray* args)) preRunblock;
+(void) addWrappertoClass:(Class) clazz andSelector:(SEL) selector withPostRunBlock:(id (^)(id<NSObject> zelf, id functionReturnValue,NSArray* args)) postRunBlock;
+(void) addWrappertoClass:(Class) clazz andSelector:(SEL) selector withPreRunBlock:(void (^)(id<NSObject> zelf,NSArray* args)) preRunblock andPostRunBlock:(id (^)(id<NSObject> zelf, id functionReturnValue,NSArray* args)) postRunBlock;

+(void) removeWrapperFrom:(id<NSObject>) target andSelector:(SEL) selector;
+(void) removeWrapperFromClass:(Class) clazz andSelector:(SEL) selector;

@end
