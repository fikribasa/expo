// Copyright 2016-present 650 Industries. All rights reserved.

#import <UMCore/UMModuleRegistry.h>

#import <EXFileSystem/EXFileSystem.h>

#import <CommonCrypto/CommonDigest.h>

#import <EXFileSystem/EXFileSystemLocalFileHandler.h>
#import <EXFileSystem/EXFileSystemAssetLibraryHandler.h>

#import <UMFileSystemInterface/UMFileSystemInterface.h>
#import <UMFileSystemInterface/UMFilePermissionModuleInterface.h>


#import <UMCore/UMEventEmitterService.h>

#import <EXFileSystem/EXSessionDownloadTaskDelegate.h>
#import <EXFileSystem/EXSessionUploadTaskDelegate.h>

NSString * const EXDownloadProgressEventName = @"expo-file-system.downloadProgress";

typedef NS_ENUM(NSInteger, EXFileSystemSessionType) {
  EXFileSystemBackgroundSession = 0,
  EXFileSystemForegroundSession = 1,
};

typedef NS_ENUM(NSInteger, EXFileSystemHTTPMethod) {
  EXFileSystemPostMethod = 0,
  EXFileSystemPutMethod = 1,
  EXFileSystemPatchMethod = 2,
};

@interface EXFileSystem ()

@property (nonatomic, strong) NSURLSession *backgroundSession;
@property (nonatomic, strong) NSURLSession *foregroundSession;
@property (nonatomic, strong) EXSessionTaskDispatcher *sessionTaskDispatcher;
@property (nonatomic, weak) UMModuleRegistry *moduleRegistry;
@property (nonatomic, weak) id<UMEventEmitterService> eventEmitter;
@property (nonatomic, strong) NSString *documentDirectory;
@property (nonatomic, strong) NSString *cachesDirectory;
@property (nonatomic, strong) NSString *bundleDirectory;

@end

@implementation EXFileSystem

UM_REGISTER_MODULE();

+ (const NSString *)exportedModuleName
{
  return @"ExponentFileSystem";
}

+ (const NSArray<Protocol *> *)exportedInterfaces
{
  return @[@protocol(UMFileSystemInterface)];
}

- (instancetype)initWithDocumentDirectory:(NSString *)documentDirectory cachesDirectory:(NSString *)cachesDirectory bundleDirectory:(NSString *)bundleDirectory
{
  if (self = [super init]) {
    _documentDirectory = documentDirectory;
    _cachesDirectory = cachesDirectory;
    _bundleDirectory = bundleDirectory;
    
    _sessionTaskDispatcher = [EXSessionTaskDispatcher new];
    _backgroundSession = [self _createSession:EXFileSystemBackgroundSession];
    _foregroundSession = [self _createSession:EXFileSystemForegroundSession];
    
    [EXFileSystem ensureDirExistsWithPath:_documentDirectory];
    [EXFileSystem ensureDirExistsWithPath:_cachesDirectory];
  }
  return self;
}

- (instancetype)init
{
  NSArray<NSString *> *documentPaths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
  NSString *documentDirectory = [documentPaths objectAtIndex:0];

  NSArray<NSString *> *cachesPaths = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES);
  NSString *cacheDirectory = [cachesPaths objectAtIndex:0];

  return [self initWithDocumentDirectory:documentDirectory
                         cachesDirectory:cacheDirectory
                         bundleDirectory:[NSBundle mainBundle].bundlePath];
}

- (void)setModuleRegistry:(UMModuleRegistry *)moduleRegistry
{
  _moduleRegistry = moduleRegistry;
  _eventEmitter = [_moduleRegistry getModuleImplementingProtocol:@protocol(UMEventEmitterService)];
}

- (NSDictionary *)constantsToExport
{
  return @{
           @"documentDirectory": _documentDirectory ? [NSURL fileURLWithPath:_documentDirectory].absoluteString : [NSNull null],
           @"cacheDirectory": _cachesDirectory ? [NSURL fileURLWithPath:_cachesDirectory].absoluteString : [NSNull null],
           @"bundleDirectory": _bundleDirectory ? [NSURL fileURLWithPath:_bundleDirectory].absoluteString : [NSNull null]
           };
}

- (NSArray<NSString *> *)supportedEvents
{
  return @[EXDownloadProgressEventName];
}

- (void)startObserving {
  
}


- (void)stopObserving {
  
}

- (void)dealloc
{
  [_sessionTaskDispatcher deactivate];
  [_backgroundSession invalidateAndCancel];
  [_foregroundSession invalidateAndCancel];
}

- (NSDictionary *)encodingMap
{
  /*
   TODO:Bacon: match node.js fs
   https://github.com/nodejs/node/blob/master/lib/buffer.js
   ascii
   base64
   binary
   hex
   ucs2/ucs-2
   utf16le/utf-16le
   utf8/utf-8
   latin1 (ISO8859-1, only in node 6.4.0+)
   */
  return @{
           @"ascii": @(NSASCIIStringEncoding),
           @"nextstep": @(NSNEXTSTEPStringEncoding),
           @"japaneseeuc": @(NSJapaneseEUCStringEncoding),
           @"utf8": @(NSUTF8StringEncoding),
           @"isolatin1": @(NSISOLatin1StringEncoding),
           @"symbol": @(NSSymbolStringEncoding),
           @"nonlossyascii": @(NSNonLossyASCIIStringEncoding),
           @"shiftjis": @(NSShiftJISStringEncoding),
           @"isolatin2": @(NSISOLatin2StringEncoding),
           @"unicode": @(NSUnicodeStringEncoding),
           @"windowscp1251": @(NSWindowsCP1251StringEncoding),
           @"windowscp1252": @(NSWindowsCP1252StringEncoding),
           @"windowscp1253": @(NSWindowsCP1253StringEncoding),
           @"windowscp1254": @(NSWindowsCP1254StringEncoding),
           @"windowscp1250": @(NSWindowsCP1250StringEncoding),
           @"iso2022jp": @(NSISO2022JPStringEncoding),
           @"macosroman": @(NSMacOSRomanStringEncoding),
           @"utf16": @(NSUTF16StringEncoding),
           @"utf16bigendian": @(NSUTF16BigEndianStringEncoding),
           @"utf16littleendian": @(NSUTF16LittleEndianStringEncoding),
           @"utf32": @(NSUTF32StringEncoding),
           @"utf32bigendian": @(NSUTF32BigEndianStringEncoding),
           @"utf32littleendian": @(NSUTF32LittleEndianStringEncoding),
           };
}

UM_EXPORT_METHOD_AS(getInfoAsync,
                    getInfoAsyncWithURI:(NSString *)uriString
                    withOptions:(NSDictionary *)options
                    resolver:(UMPromiseResolveBlock)resolve
                    rejecter:(UMPromiseRejectBlock)reject)
{
  NSURL *uri = [NSURL URLWithString:uriString];
  // no scheme provided in uri, handle as a local path and add 'file://' scheme
  if (!uri.scheme) {
    uri = [NSURL fileURLWithPath:uriString isDirectory:false];
  }
  if (!([self permissionsForURI:uri] & UMFileSystemPermissionRead)) {
    reject(@"E_FILESYSTEM_PERMISSIONS",
           [NSString stringWithFormat:@"File '%@' isn't readable.", uri],
           nil);
    return;
  }
  
  if ([uri.scheme isEqualToString:@"file"]) {
    [EXFileSystemLocalFileHandler getInfoForFile:uri withOptions:options resolver:resolve rejecter:reject];
  } else if ([uri.scheme isEqualToString:@"assets-library"] || [uri.scheme isEqualToString:@"ph"]) {
    [EXFileSystemAssetLibraryHandler getInfoForFile:uri withOptions:options resolver:resolve rejecter:reject];
  } else {
    reject(@"E_FILESYSTEM_INVALID_URI",
           [NSString stringWithFormat:@"Unsupported URI scheme for '%@'", uri],
           nil);
  }
}

UM_EXPORT_METHOD_AS(readAsStringAsync,
                    readAsStringAsyncWithURI:(NSString *)uriString
                    withOptions:(NSDictionary *)options
                    resolver:(UMPromiseResolveBlock)resolve
                    rejecter:(UMPromiseRejectBlock)reject)
{
  NSURL *uri = [NSURL URLWithString:uriString];
  // no scheme provided in uri, handle as a local path and add 'file://' scheme
  if (!uri.scheme) {
    uri = [NSURL fileURLWithPath:uriString isDirectory:false];
  }
  if (!([self permissionsForURI:uri] & UMFileSystemPermissionRead)) {
    reject(@"E_FILESYSTEM_PERMISSIONS",
           [NSString stringWithFormat:@"File '%@' isn't readable.", uri],
           nil);
    return;
  }
  
  if ([uri.scheme isEqualToString:@"file"]) {
    NSString *encodingType = @"utf8";
    if (options[@"encoding"] && [options[@"encoding"] isKindOfClass:[NSString class]]) {
      encodingType = [options[@"encoding"] lowercaseString];
    }
    if ([encodingType isEqualToString:@"base64"]) {
      NSFileHandle *file = [NSFileHandle fileHandleForReadingAtPath:uri.path];
      if (file == nil) {
        reject(@"E_FILE_NOT_READ",
               [NSString stringWithFormat:@"File '%@' could not be read.", uri.path],
               nil);
        return;
      }
      // position and length are used as a cursor/paging system.
      if ([options[@"position"] isKindOfClass:[NSNumber class]]) {
        [file seekToFileOffset:[options[@"position"] intValue]];
      }
      
      NSData *data;
      if ([options[@"length"] isKindOfClass:[NSNumber class]]) {
        data = [file readDataOfLength:[options[@"length"] intValue]];
      } else {
        data = [file readDataToEndOfFile];
      }
      resolve([data base64EncodedStringWithOptions:NSDataBase64EncodingEndLineWithLineFeed]);
    } else {
      NSUInteger encoding = NSUTF8StringEncoding;
      id possibleEncoding = [[self encodingMap] valueForKey:encodingType];
      if (possibleEncoding != nil) {
        encoding = [possibleEncoding integerValue];
      }
      NSError *error;
      NSString *string = [NSString stringWithContentsOfFile:uri.path encoding:encoding error:&error];
      if (string) {
        resolve(string);
      } else {
        reject(@"E_FILE_NOT_READ",
               [NSString stringWithFormat:@"File '%@' could not be read.", uri],
               error);
      }
    }
  } else {
    reject(@"E_FILESYSTEM_INVALID_URI",
           [NSString stringWithFormat:@"Unsupported URI scheme for '%@'", uri],
           nil);
  }
}

UM_EXPORT_METHOD_AS(writeAsStringAsync,
                    writeAsStringAsyncWithURI:(NSString *)uriString
                    withString:(NSString *)string
                    withOptions:(NSDictionary *)options
                    resolver:(UMPromiseResolveBlock)resolve
                    rejecter:(UMPromiseRejectBlock)reject)
{
  NSURL *uri = [NSURL URLWithString:uriString];
  if (!([self permissionsForURI:uri] & UMFileSystemPermissionWrite)) {
    reject(@"E_FILESYSTEM_PERMISSIONS",
           [NSString stringWithFormat:@"File '%@' isn't writable.", uri],
           nil);
    return;
  }
  
  if ([uri.scheme isEqualToString:@"file"]) {
    NSString *encodingType = @"utf8";
    if ([options[@"encoding"] isKindOfClass:[NSString class]]) {
      encodingType = [options[@"encoding"] lowercaseString];
    }
    if ([encodingType isEqualToString:@"base64"]) {
      dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSData *imageData = [[NSData alloc] initWithBase64EncodedString:string options:NSDataBase64DecodingIgnoreUnknownCharacters];
        if (imageData) {
          // TODO:Bacon: Should we surface `attributes`?
          if ([[NSFileManager defaultManager] createFileAtPath:uri.path contents:imageData attributes:nil]) {
            resolve([NSNull null]);
          } else {
            return reject(@"E_FILE_UNKNOWN",
                          [NSString stringWithFormat:@"No such file or directory '%@'", uri.path],
                          nil);
          }
        } else {
          reject(@"E_INVALID_FORMAT",
                 @"Failed to parse base64 string.",
                 nil);
        }
      });
    } else {
      NSUInteger encoding = NSUTF8StringEncoding;
      id possibleEncoding = [[self encodingMap] valueForKey:encodingType];
      if (possibleEncoding != nil) {
        encoding = [possibleEncoding integerValue];
      }
      
      NSError *error;
      if ([string writeToFile:uri.path atomically:YES encoding:encoding error:&error]) {
        resolve([NSNull null]);
      } else {
        reject(@"E_FILE_NOT_WRITTEN",
               [NSString stringWithFormat:@"File '%@' could not be written.", uri],
               error);
      }
    }
  } else {
    reject(@"E_FILESYSTEM_INVALID_URI",
           [NSString stringWithFormat:@"Unsupported URI scheme for '%@'", uri],
           nil);
  }
}

UM_EXPORT_METHOD_AS(deleteAsync,
                    deleteAsyncWithURI:(NSString *)uriString
                    withOptions:(NSDictionary *)options
                    resolver:(UMPromiseResolveBlock)resolve
                    rejecter:(UMPromiseRejectBlock)reject)
{
  NSURL *uri = [NSURL URLWithString:uriString];
  if (!([self permissionsForURI:[uri URLByAppendingPathComponent:@".."]] & UMFileSystemPermissionWrite)) {
    reject(@"E_FILESYSTEM_PERMISSIONS",
           [NSString stringWithFormat:@"Location '%@' isn't deletable.", uri],
           nil);
    return;
  }
  
  if ([uri.scheme isEqualToString:@"file"]) {
    NSString *path = uri.path;
    if ([self _checkIfFileExists:path]) {
      NSError *error;
      if ([[NSFileManager defaultManager] removeItemAtPath:path error:&error]) {
        resolve([NSNull null]);
      } else {
        reject(@"E_FILE_NOT_DELETED",
               [NSString stringWithFormat:@"File '%@' could not be deleted.", uri],
               error);
      }
    } else {
      if (options[@"idempotent"]) {
        resolve([NSNull null]);
      } else {
        reject(@"E_FILE_NOT_FOUND",
               [NSString stringWithFormat:@"File '%@' could not be deleted because it could not be found.", uri],
               nil);
      }
    }
  } else {
    reject(@"E_FILESYSTEM_INVALID_URI",
           [NSString stringWithFormat:@"Unsupported URI scheme for '%@'", uri],
           nil);
  }
}

UM_EXPORT_METHOD_AS(moveAsync,
                    moveAsyncWithOptions:(NSDictionary *)options
                    resolver:(UMPromiseResolveBlock)resolve
                    rejecter:(UMPromiseRejectBlock)reject)
{
  NSURL *from = [NSURL URLWithString:options[@"from"]];
  if (!from) {
    reject(@"E_MISSING_PARAMETER", @"Need a `from` location.", nil);
    return;
  }
  if (!([self permissionsForURI:[from URLByAppendingPathComponent:@".."]] & UMFileSystemPermissionWrite)) {
    reject(@"E_FILESYSTEM_PERMISSIONS",
           [NSString stringWithFormat:@"Location '%@' isn't movable.", from],
           nil);
    return;
  }
  NSURL *to = [NSURL URLWithString:options[@"to"]];
  if (!to) {
    reject(@"E_MISSING_PARAMETER", @"Need a `to` location.", nil);
    return;
  }
  if (!([self permissionsForURI:to] & UMFileSystemPermissionWrite)) {
    reject(@"E_FILESYSTEM_PERMISSIONS",
           [NSString stringWithFormat:@"File '%@' isn't writable.", to],
           nil);
    return;
  }
  
  // NOTE: The destination-delete and the move should happen atomically, but we hope for the best for now
  if ([from.scheme isEqualToString:@"file"]) {
    NSString *fromPath = [from.path stringByStandardizingPath];
    NSString *toPath = [to.path stringByStandardizingPath];
    NSError *error;
    if ([self _checkIfFileExists:toPath]) {
      if (![[NSFileManager defaultManager] removeItemAtPath:toPath error:&error]) {
        reject(@"E_FILE_NOT_MOVED",
               [NSString stringWithFormat:@"File '%@' could not be moved to '%@' because a file already exists at "
                "the destination and could not be deleted.", from, to],
               error);
        return;
      }
    }
    if ([[NSFileManager defaultManager] moveItemAtPath:fromPath toPath:toPath error:&error]) {
      resolve([NSNull null]);
    } else {
      reject(@"E_FILE_NOT_MOVED",
             [NSString stringWithFormat:@"File '%@' could not be moved to '%@'.", from, to],
             error);
    }
  } else {
    reject(@"E_FILESYSTEM_INVALID_URI",
           [NSString stringWithFormat:@"Unsupported URI scheme for '%@'", from],
           nil);
  }
}

UM_EXPORT_METHOD_AS(copyAsync,
                    copyAsyncWithOptions:(NSDictionary *)options
                    resolver:(UMPromiseResolveBlock)resolve
                    rejecter:(UMPromiseRejectBlock)reject)
{
  NSURL *from = [NSURL URLWithString:options[@"from"]];
  if (!from) {
    reject(@"E_MISSING_PARAMETER", @"Need a `from` location.", nil);
    return;
  }
  if (!([self permissionsForURI:from] & UMFileSystemPermissionRead)) {
    reject(@"E_FILESYSTEM_PERMISSIONS",
           [NSString stringWithFormat:@"File '%@' isn't readable.", from],
           nil);
    return;
  }
  NSURL *to = [NSURL URLWithString:options[@"to"]];
  if (!to) {
    reject(@"E_MISSING_PARAMETER", @"Need a `to` location.", nil);
    return;
  }
  if (!([self permissionsForURI:to] & UMFileSystemPermissionWrite)) {
    reject(@"E_FILESYSTEM_PERMISSIONS",
           [NSString stringWithFormat:@"File '%@' isn't writable.", to],
           nil);
    return;
  }
  
  if ([from.scheme isEqualToString:@"file"]) {
    [EXFileSystemLocalFileHandler copyFrom:from to:to resolver:resolve rejecter:reject];
  } else if ([from.scheme isEqualToString:@"assets-library"] || [from.scheme isEqualToString:@"ph"]) {
    [EXFileSystemAssetLibraryHandler copyFrom:from to:to resolver:resolve rejecter:reject];
  } else {
    reject(@"E_FILESYSTEM_INVALID_URI",
           [NSString stringWithFormat:@"Unsupported URI scheme for '%@'", from],
           nil);
  }
}

UM_EXPORT_METHOD_AS(makeDirectoryAsync,
                    makeDirectoryAsyncWithURI:(NSString *)uriString
                    withOptions:(NSDictionary *)options
                    resolver:(UMPromiseResolveBlock)resolve
                    rejecter:(UMPromiseRejectBlock)reject)
{
  
  NSURL *uri = [NSURL URLWithString:uriString];
  if (!([self permissionsForURI:uri] & UMFileSystemPermissionWrite)) {
    reject(@"E_FILESYSTEM_PERMISSIONS",
           [NSString stringWithFormat:@"Directory '%@' could not be created because the location isn't writable.", uri],
           nil);
    return;
  }
  
  if ([uri.scheme isEqualToString:@"file"]) {
    NSError *error;
    if ([[NSFileManager defaultManager] createDirectoryAtPath:uri.path
                                  withIntermediateDirectories:[options[@"intermediates"] boolValue]
                                                   attributes:nil
                                                        error:&error]) {
      resolve([NSNull null]);
    } else {
      reject(@"E_DIRECTORY_NOT_CREATED",
             [NSString stringWithFormat:@"Directory '%@' could not be created.", uri],
             error);
    }
  } else {
    reject(@"E_FILESYSTEM_INVALID_URI",
           [NSString stringWithFormat:@"Unsupported URI scheme for '%@'", uri],
           nil);
  }
}

UM_EXPORT_METHOD_AS(readDirectoryAsync,
                    readDirectoryAsyncWithURI:(NSString *)uriString
                    withOptions:(NSDictionary *)options
                    resolver:(UMPromiseResolveBlock)resolve
                    rejecter:(UMPromiseRejectBlock)reject)
{
  NSURL *uri = [NSURL URLWithString:uriString];
  if (!([self permissionsForURI:uri] & UMFileSystemPermissionRead)) {
    reject(@"E_FILESYSTEM_PERMISSIONS",
           [NSString stringWithFormat:@"Location '%@' isn't readable.", uri],
           nil);
    return;
  }
  
  if ([uri.scheme isEqualToString:@"file"]) {
    NSError *error;
    NSArray<NSString *> *children = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:uri.path error:&error];
    if (children) {
      resolve(children);
    } else {
      reject(@"E_DIRECTORY_NOT_READ",
             [NSString stringWithFormat:@"Directory '%@' could not be read.", uri],
             error);
    }
  } else {
    reject(@"E_FILESYSTEM_INVALID_URI",
           [NSString stringWithFormat:@"Unsupported URI scheme for '%@'", uri],
           nil);
  }
}

UM_EXPORT_METHOD_AS(downloadAsync,
                    downloadAsyncWithUrl:(NSString *)urlString
                                localURI:(NSString *)localUriString
                                 options:(NSDictionary *)options
                                resolver:(UMPromiseResolveBlock)resolve
                                rejecter:(UMPromiseRejectBlock)reject)
{
  NSURL *url = [NSURL URLWithString:urlString];
  NSURL *localUri = [NSURL URLWithString:localUriString];
  if (!([self checkIfFileDirExists:localUri.path])) {
    reject(@"ERR_FILESYSTEM_WRONG_DESTINATION",
           [NSString stringWithFormat:@"Directory for %@ doesn't exist.", localUriString],
           nil);
    return;
  }
  if (!([self permissionsForURI:localUri] & UMFileSystemPermissionWrite)) {
    reject(@"ERR_FILESYSTEM_PERMISSIONS",
           [NSString stringWithFormat:@"File '%@' isn't writable.", localUri],
           nil);
    return;
  }
  if (![self _checkHeadersDictionary:options[@"headers"]]) {
    reject(@"ERR_FILESYSTEM_INVALID_HEADERS",
           @"Invalid headers dictionary. Keys and values should be strings.",
           nil);
    return;
  }

  NSURLRequest *request = [self _createRequest:url headers:options[@"headers"]];
  EXFileSystemSessionType type = [self _importSessionType:options[@"sessionType"]];
  NSURLSessionDownloadTask *task = [[self _sessionForType:type] downloadTaskWithRequest:request];
  EXSessionTaskDelegate *taskDelegate = [[EXSessionDownloadTaskDelegate alloc] initWithResolve:resolve
                                                                                        reject:reject
                                                                                      localUrl:localUri
                                                                            shouldCalculateMd5:[options[@"md5"] boolValue]];
  [_sessionTaskDispatcher registerTaskDelegate:taskDelegate forTask:task];
  [task resume];
}

UM_EXPORT_METHOD_AS(uploadAsync,
                    uploadAsync:(NSString *)urlString
                       localURI:(NSString *)fileUriString
                        options:(NSDictionary *)options
                       resolver:(UMPromiseResolveBlock)resolve
                       rejecter:(UMPromiseRejectBlock)reject)
{
  NSURL *fileUri = [NSURL URLWithString:fileUriString];
  if (![fileUri.scheme isEqualToString:@"file"]) {
    reject(@"ERR_FILESYSTEM_PERMISSIONS",
           [NSString stringWithFormat:@"Cannot upload file '%@'. Only 'file://' URI are supported.", fileUri],
           nil);
    return;
  }
  if (!([self _checkIfFileExists:fileUri.path])) {
    reject(@"ERR_FILE_NOT_EXISTS",
           [NSString stringWithFormat:@"File '%@' does not exist.", fileUri],
           nil);
    return;
  }
  if (![self _checkHeadersDictionary:options[@"headers"]]) {
    reject(@"ERR_FILESYSTEM_INVALID_HEADERS_DICTIONARY",
           @"Invalid headers dictionary. Keys and values should be strings.",
           nil);
    return;
  }

  NSURLRequest *request = [self _createRequest:[NSURL URLWithString:urlString] headers:options[@"headers"]];
  if (options[@"httpMethod"]) {
    NSString *httpMethod = [self _importHttpMethod:options[@"httpMethod"]];
    if (!httpMethod) {
      reject(@"ERR_FILESYSTEM_INVALID_HTTP_METHOD",
             [NSString stringWithFormat:@"Invalid http method %@", options[@"httpMethod"]],
             nil);
      return;
    }
    
    NSMutableURLRequest *mutableRequest = [request mutableCopy];
    [mutableRequest setHTTPMethod:httpMethod];
    request = mutableRequest;
  }
  
  EXFileSystemSessionType type = [self _importSessionType:options[@"sessionType"]];
  NSURLSessionUploadTask *task = [[self _sessionForType:type] uploadTaskWithRequest:request fromFile:fileUri];
  EXSessionTaskDelegate *taskDelegate = [[EXSessionUploadTaskDelegate alloc] initWithResolve:resolve reject:reject];
  [_sessionTaskDispatcher registerTaskDelegate:taskDelegate forTask:task];
  [task resume];
}

UM_EXPORT_METHOD_AS(downloadResumableStartAsync,
                    downloadResumableStartAsyncWithUrl:(NSString *)urlString
                                               fileURI:(NSString *)fileUri
                                                  uuid:(NSString *)uuid
                                               options:(NSDictionary *)options
                                            resumeData:(NSString *)data
                                              resolver:(UMPromiseResolveBlock)resolve
                                              rejecter:(UMPromiseRejectBlock)reject)
{
  NSURL *url = [NSURL URLWithString:urlString];
  NSURL *localUrl = [NSURL URLWithString:fileUri];
  if (!([self checkIfFileDirExists:localUrl.path])) {
    reject(@"ERR_FILESYSTEM_WRONG_DESTINATION",
           [NSString stringWithFormat:@"Directory for %@ doesn't exist.", fileUri],
           nil);
    return;
  }
  if (![localUrl.scheme isEqualToString:@"file"]) {
    reject(@"ERR_FILESYSTEM_PERMISSIONS",
           [NSString stringWithFormat:@"Cannot download to '%@': only 'file://' URI destinations are supported.", fileUri],
           nil);
    return;
  }
  
  NSString *path = localUrl.path;
  if (!([self _permissionsForPath:path] & UMFileSystemPermissionWrite)) {
    reject(@"ERR_FILESYSTEM_PERMISSIONS",
           [NSString stringWithFormat:@"File '%@' isn't writable.", fileUri],
           nil);
    return;
  }
  
  if (![self _checkHeadersDictionary:options[@"headers"]]) {
    reject(@"ERR_FILESYSTEM_INVALID_HEADERS_DICTIONARY",
           @"Invalid headers dictionary. Keys and values should be strings.",
           nil);
    return;
  }
  
  NSData *resumeData = data ? [[NSData alloc] initWithBase64EncodedString:data options:0] : nil;
  [self _downloadResumableCreateSessionWithUrl:url
                                       fileUrl:localUrl
                                          uuid:uuid
                                        optins:options
                                    resumeData:resumeData
                                       resolve:resolve
                                        reject:reject];
}

UM_EXPORT_METHOD_AS(downloadResumablePauseAsync,
                    downloadResumablePauseAsyncWithUUID:(NSString *)uuid
                    resolver:(UMPromiseResolveBlock)resolve
                    rejecter:(UMPromiseRejectBlock)reject)
{
  NSURLSessionDownloadTask *task = [_sessionTaskDispatcher resumableDownload:uuid];
  if (!task) {
    reject(@"ERR_UNABLE_TO_PAUSE",
           [NSString stringWithFormat:@"There is no download object with UUID: %@", uuid],
           nil);
    return;
  }
  
  UM_WEAKIFY(self);
  [task cancelByProducingResumeData:^(NSData * _Nullable resumeData) {
    UM_ENSURE_STRONGIFY(self);
    resolve(@{ @"resumeData": UMNullIfNil([resumeData base64EncodedStringWithOptions:0]) });
    [self.sessionTaskDispatcher removeResumableDownload:uuid];
  }];
}

UM_EXPORT_METHOD_AS(getFreeDiskStorageAsync, getFreeDiskStorageAsyncWithResolver:(UMPromiseResolveBlock)resolve rejecter:(UMPromiseRejectBlock)reject)
{
  if(![self freeDiskStorage]) {
    reject(@"ERR_FILESYSTEM", @"Unable to determine free disk storage capacity", nil);
  } else {
    resolve([self freeDiskStorage]);
  }
}

UM_EXPORT_METHOD_AS(getTotalDiskCapacityAsync, getTotalDiskCapacityAsyncWithResolver:(UMPromiseResolveBlock)resolve rejecter:(UMPromiseRejectBlock)reject)
{
  if(![self totalDiskCapacity]) {
    reject(@"ERR_FILESYSTEM", @"Unable to determine total disk capacity", nil);
  } else {
    resolve([self totalDiskCapacity]);
  }
}

#pragma mark - Internal methods

- (NSURLRequest *)_createRequest:(NSURL *)url headers:(NSDictionary * _Nullable)headers
{
  NSMutableURLRequest *request = [[NSMutableURLRequest alloc] initWithURL:url];
  if (headers != nil) {
    for (NSString *headerKey in headers) {
      [request setValue:[headers valueForKey:headerKey] forHTTPHeaderField:headerKey];
    }
  }
  
  return request;
}

- (EXFileSystemSessionType)_importSessionType:(NSNumber * _Nullable)type
{
  return [type intValue] ?: EXFileSystemBackgroundSession;
}

- (NSURLSession *)_sessionForType:(EXFileSystemSessionType)type
{
  switch (type) {
    case EXFileSystemBackgroundSession:
      return _backgroundSession;
    case EXFileSystemForegroundSession:
      return _foregroundSession;
  }
  return nil;
}

- (BOOL)_checkHeadersDictionary:(NSDictionary * _Nullable)headers
{
  for (id key in [headers allKeys]) {
    if (![key isKindOfClass:[NSString class]] || ![headers[key] isKindOfClass:[NSString class]]) {
      return false;
    }
  }
  
  return true;
}

- (NSURLSession *)_createSession:(EXFileSystemSessionType)type
{
  NSURLSessionConfiguration *sessionConfiguration;
  if (type == EXFileSystemForegroundSession) {
    sessionConfiguration = [NSURLSessionConfiguration defaultSessionConfiguration];
  } else {
    sessionConfiguration = [NSURLSessionConfiguration backgroundSessionConfigurationWithIdentifier:[[NSUUID UUID] UUIDString]];
  }
  sessionConfiguration.requestCachePolicy = NSURLRequestReloadIgnoringLocalCacheData;
  sessionConfiguration.URLCache = nil;
  return [NSURLSession sessionWithConfiguration:sessionConfiguration
                                       delegate:_sessionTaskDispatcher
                                  delegateQueue:nil];
}

- (BOOL)_checkIfFileExists:(NSString *)path
{
  return [[NSFileManager defaultManager] fileExistsAtPath:path];
}

- (NSString * _Nullable)_importHttpMethod:(NSNumber *)httpMethod
{
  switch ([httpMethod intValue]) {
    case EXFileSystemPostMethod:
      return @"POST";
    case EXFileSystemPutMethod:
      return @"PUT";
    case EXFileSystemPatchMethod:
      return @"PATCH";
  }
  return nil;
}

- (void)_downloadResumableCreateSessionWithUrl:(NSURL *)url
                                       fileUrl:(NSURL *)fileUrl
                                          uuid:(NSString *)uuid
                                        optins:(NSDictionary *)options
                                    resumeData:(NSData * _Nullable)resumeData
                                       resolve:(UMPromiseResolveBlock)resolve
                                        reject:(UMPromiseRejectBlock)reject
{
  UM_WEAKIFY(self);
  EXDownloadDelegateOnWriteCallback onWrite = ^(NSURLSessionDownloadTask *task, int64_t bytesWritten, int64_t totalBytesWritten, int64_t totalBytesExpectedToWrite) {
    UM_ENSURE_STRONGIFY(self);
    [self sendEventWithName:EXDownloadProgressEventName
                       body:@{
                             @"uuid": uuid,
                             @"data": @{
                                 @"totalBytesWritten": @(totalBytesWritten),
                                 @"totalBytesExpectedToWrite": @(totalBytesExpectedToWrite),
                             },
                           }];
  };
  
  NSURLSessionDownloadTask *downloadTask;
  EXFileSystemSessionType type = [self _importSessionType:options[@"sessionType"]];
  NSURLSession *session = [self _sessionForType:type];
  if (resumeData) {
    downloadTask = [session downloadTaskWithResumeData:resumeData];
  } else {
    NSURLRequest *request = [self _createRequest:url headers:options[@"headers"]];
    downloadTask = [session downloadTaskWithRequest:request];
  }
  EXSessionTaskDelegate *taskDelegate = [[EXSessionResumableDownloadTaskDelegate alloc] initWithResolve:resolve
                                                                                           reject:reject
                                                                                         localUrl:fileUrl
                                                                               shouldCalculateMd5:[options[@"md5"] boolValue]
                                                                                  onWriteCallback:onWrite
                                                                                             uuid:uuid];
  [_sessionTaskDispatcher registerTaskDelegate:taskDelegate forTask:downloadTask];
  [_sessionTaskDispatcher registerResumableDownloadTask:downloadTask uuid:uuid];
  [downloadTask resume];
}

- (UMFileSystemPermissionFlags)_permissionsForPath:(NSString *)path
{
  return [[_moduleRegistry getModuleImplementingProtocol:@protocol(UMFilePermissionModuleInterface)] getPathPermissions:(NSString *)path];
}

- (void)sendEventWithName:(NSString *)eventName body:(id)body
{
  if (_eventEmitter != nil) {
    [_eventEmitter sendEventWithName:eventName body:body];
  }
}

- (NSDictionary *)documentFileSystemAttributes {
  return [[NSFileManager defaultManager] attributesOfFileSystemForPath:_documentDirectory error:nil];
}

#pragma mark - Public utils

- (UMFileSystemPermissionFlags)permissionsForURI:(NSURL *)uri
{
  NSArray *validSchemas = @[
                            @"assets-library",
                            @"http",
                            @"https",
                            @"ph",
                            ];
  if ([validSchemas containsObject:uri.scheme]) {
    return UMFileSystemPermissionRead;
  }
  if ([uri.scheme isEqualToString:@"file"]) {
    return [self _permissionsForPath:uri.path];
  }
  return UMFileSystemPermissionNone;
}

- (BOOL)checkIfFileDirExists:(NSString *)path
{
  NSString *dir = [path stringByDeletingLastPathComponent];
  return [self _checkIfFileExists:dir];
}

#pragma mark - Class methods

- (BOOL)ensureDirExistsWithPath:(NSString *)path
{
  return [EXFileSystem ensureDirExistsWithPath:path];
}

+ (BOOL)ensureDirExistsWithPath:(NSString *)path
{
  BOOL isDir = NO;
  NSError *error;
  BOOL exists = [[NSFileManager defaultManager] fileExistsAtPath:path isDirectory:&isDir];
  if (!(exists && isDir)) {
    [[NSFileManager defaultManager] createDirectoryAtPath:path withIntermediateDirectories:YES attributes:nil error:&error];
    if (error) {
      return NO;
    }
  }
  return YES;
}

- (NSString *)generatePathInDirectory:(NSString *)directory withExtension:(NSString *)extension
{
  return [EXFileSystem generatePathInDirectory:directory withExtension:extension];
}

+ (NSString *)generatePathInDirectory:(NSString *)directory withExtension:(NSString *)extension
{
  NSString *fileName = [[[NSUUID UUID] UUIDString] stringByAppendingString:extension];
  [EXFileSystem ensureDirExistsWithPath:directory];
  return [directory stringByAppendingPathComponent:fileName];
}

- (NSNumber *)totalDiskCapacity {
  NSDictionary *storage = [self documentFileSystemAttributes];
  
  if (storage) {
    NSNumber *fileSystemSizeInBytes = storage[NSFileSystemSize];
    return fileSystemSizeInBytes;
  }
  return nil;
}

- (NSNumber *)freeDiskStorage {
  NSDictionary *storage = [self documentFileSystemAttributes];
  
  if (storage) {
    NSNumber *freeFileSystemSizeInBytes = storage[NSFileSystemFreeSize];
    return freeFileSystemSizeInBytes;
  }
  return nil;
}

@end
