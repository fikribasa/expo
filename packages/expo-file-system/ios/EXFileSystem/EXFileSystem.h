// Copyright 2016-present 650 Industries. All rights reserved.

#import <Foundation/Foundation.h>
#import <UMCore/UMExportedModule.h>
#import <UMCore/UMModuleRegistryConsumer.h>
#import <UMCore/UMEventEmitter.h>
#import <UMFileSystemInterface/UMFileSystemInterface.h>
#import <EXFileSystem/EXSessionResumableDownloadTaskDelegate.h>
#import <EXFileSystem/EXSessionTaskDispatcher.h>

@interface EXFileSystem : UMExportedModule <UMEventEmitter, UMModuleRegistryConsumer, UMFileSystemInterface, NSURLSessionDelegate>

@property (nonatomic, readonly) NSString *documentDirectory;
@property (nonatomic, readonly) NSString *cachesDirectory;
@property (nonatomic, readonly) NSString *bundleDirectory;

- (instancetype)initWithDocumentDirectory:(NSString *)documentDirectory cachesDirectory:(NSString *)cachesDirectory bundleDirectory:(NSString *)bundleDirectory;

- (UMFileSystemPermissionFlags)permissionsForURI:(NSURL *)uri;

- (BOOL)ensureDirExistsWithPath:(NSString *)path;

- (NSString *)generatePathInDirectory:(NSString *)directory withExtension:(NSString *)extension;

@end

@protocol EXFileSystemHandler

+ (void)getInfoForFile:(NSURL *)fileUri
           withOptions:(NSDictionary *)optionxs
              resolver:(UMPromiseResolveBlock)resolve
              rejecter:(UMPromiseRejectBlock)reject;

+ (void)copyFrom:(NSURL *)from
              to:(NSURL *)to
        resolver:(UMPromiseResolveBlock)resolve
        rejecter:(UMPromiseRejectBlock)reject;

@end

@interface NSData (EXFileSystem)

- (NSString *)md5String;

@end
