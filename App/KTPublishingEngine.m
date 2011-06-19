//
//  KTExportEngine.m
//  Marvel
//
//  Created by Mike on 12/12/2008.
//  Copyright 2008-2011 Karelia Software. All rights reserved.
//

#import "KTPublishingEngine.h"

#import "KTPage+Internal.h"
#import "KTDesign.h"
#import "KTHostProperties.h"
#import "KTSite.h"
#import "KTMaster.h"
#import "SVPublishingDigestStorage.h"
#import "SVMediaRequest.h"
#import "KTPage+Internal.h"
#import "SVPublishingHTMLContext.h"
#import "SVPublishingRecord.h"
#import "KTTranscriptController.h"

#import "SVGoogleSitemapPinger.h"

#import "SVImageScalingOperation.h"
#import "KTImageScalingURLProtocol.h"

#import "NSBundle+KTExtensions.h"
#import "NSString+KTExtensions.h"

#import "NSData+Karelia.h"
#import "NSError+Karelia.h"
#import "NSObject+Karelia.h"
#import "NSString+Karelia.h"
#import "KSURLUtilities.h"
#import "KSPathUtilities.h"

#import "KSCSSWriter.h"
#import "KSPlugInWrapper.h"
#import "KSSHA1Stream.h"
#import "KSThreadProxy.h"

#import "Debug.h"
#import "Registration.h"

int kMaxNumberOfFreePublishedPages = 5;	// This is the constant value of how many pages max to publish when it's the free/lite/demo/unlicensed state.

NSString *KTPublishingEngineErrorDomain = @"KTPublishingEngineError";


@interface SVPublishingRecord ()
- (void)setSHA1Digest:(NSData *)digest;
- (void)setContentHash:(NSData *)digest;
@end


#pragma mark -


@interface KTPublishingEngine ()

@property(retain) NSOperation *startNextPhaseOperation;
@property(assign) NSUInteger countOfPublishedItems;

- (void)publishDesign;
- (void)publishMainCSSToPath:(NSString *)cssUploadPath;
- (NSString *)publishMediaWithRequest:(SVMediaRequest *)request cachedData:(NSData *)data SHA1Digest:(NSData *)digest;

- (void)setRootTransferRecord:(CKTransferRecord *)rootRecord;

- (CKTransferRecord *)uploadData:(NSData *)data toPath:(NSString *)remotePath;
- (CKTransferRecord *)uploadContentsOfURL:(NSURL *)localURL toPath:(NSString *)remotePath;

- (void)didEnqueueUpload:(CKTransferRecord *)record toDirectory:(CKTransferRecord *)parent;

@end


@interface KTPublishingEngine (SubclassSupportPrivate)

// Resources
- (void)addResourceFile:(NSURL *)resourceURL;

- (CKTransferRecord *)createDirectory:(NSString *)remotePath;
- (unsigned long)remoteFilePermissions;
- (unsigned long)remoteDirectoryPermissions;

@end


#pragma mark -


@implementation KTPublishingEngine

#pragma mark Init & Dealloc

/*  Subfolder can be either nil (there isn't one), or a path relative to the doc root. Exporting
 *  never uses a subfolder, but full-on publishing can.
 */
- (id)initWithSite:(KTSite *)site
  documentRootPath:(NSString *)docRoot
     subfolderPath:(NSString *)subfolder
{
	OBPRECONDITION(site);
    
    if (!docRoot) docRoot = @"";    // We need a string that can receive -stringByAppendingPathComponent: messages
    OBASSERT(docRoot);
    
    
    if (self = [self init])
	{
		_site = [site retain];
        
        _digestStorage = [[SVPublishingDigestStorage alloc] init];
        
        _plugInCSS = [[NSMutableArray alloc] init];
        
        _documentRootPath = [docRoot copy];
        _subfolderPath = [subfolder copy];
        
        
        _diskQueue = [[NSOperationQueue alloc] init];
        [_diskQueue setMaxConcurrentOperationCount:1];
        
        _defaultQueue = [[NSOperationQueue alloc] init];
        
        // Name them for debugging
        if ([NSOperationQueue instancesRespondToSelector:@selector(setName:)])
        {
            [_diskQueue performSelector:@selector(setName:) withObject:@"KTPublishingEngine: Disk Access Queue"];
            [_defaultQueue performSelector:@selector(setName:) withObject:@"KTPublishingEngine: Default Queue"];
        }
        
        
        // Page ID cache
        NSArray *pages = [[site managedObjectContext] fetchAllObjectsForEntityForName:@"SiteItem"
                                                                                error:NULL];
        
        _pagesByID = [[NSDictionary alloc] initWithObjects:pages
                                                   forKeys:[pages valueForKey:@"uniqueID"]];
        
        
        // Content Hash cache
        NSArray *records = [[site managedObjectContext]
                            fetchAllObjectsForEntityForName:@"FilePublishingRecord"
                            predicate:[NSPredicate predicateWithFormat:@"contentHash != nil"]
                            error:NULL];
        
        _publishingRecordsByContentHash = [[NSMutableDictionary alloc]
                                           initWithObjects:records
                                           forKeys:[records valueForKey:@"contentHash"]];
	}
	
	return self;
}

- (void)dealloc
{
    // The connection etc. should already have been shut down
    OBASSERT(!_connection);
    
    [_baseTransferRecord release];
    [_rootTransferRecord release];
    [_site release];
	[_documentRootPath release];
    [_subfolderPath release];
    
    [_digestStorage release];
    
    [_plugInCSS release];
    
    [_defaultQueue release];
    [_diskQueue release];
    [_nextOp release];
    
    [_pagesByID release];
	[_publishingRecordsByContentHash release];
    
	[super dealloc];
}

#pragma mark Simple Accessors

- (KTSite *)site { return _site; }
- (NSString *)documentRootPath { return _documentRootPath; }
- (NSString *)subfolderPath { return _subfolderPath; }
    
/*  Combines doc root and subfolder to get the directory that all content goes into
 */
- (NSString *)baseRemotePath
{
    NSString *result = [[self documentRootPath] stringByAppendingPathComponent:[self subfolderPath]];
    return result;
}

- (SVSiteItem *)siteItemWithUniqueID:(NSString *)ID;
{
    SVSiteItem *result = [_pagesByID objectForKey:ID];
    if (!result)
    {
        // It's very rare to look up a page that doesn't exist, so we can afford to make the sure the page doesn't really exist
        result = [SVSiteItem pageWithUniqueID:ID inManagedObjectContext:[[self site] managedObjectContext]];
    }
    
    return result;
}

@synthesize digestStorage = _digestStorage;

#pragma mark Overall flow control

- (void)start
{
	self.countOfPublishedItems = 0;
	
	if ([self status] != KTPublishingEngineStatusNotStarted) return;
    _status = KTPublishingEngineStatusGatheringMedia;
    
    [self main];
}

- (void)main
{
    // Setup connection and transfer records
    [self createConnection];
    [self setRootTransferRecord:[CKTransferRecord rootRecordWithPath:[[self documentRootPath] ks_standardizedPOSIXPath]]];
    
    
    // Successful?
    if ([self status] <= KTPublishingEngineStatusUploading)
    {
        // Store next operation so it can receive dependencies
        NSOperation *nextOp = [[NSInvocationOperation alloc]
                                         initWithTarget:self
                                         selector:@selector(mainPublishing)
                                         object:nil];
        [self setStartNextPhaseOperation:nextOp];
        
        
        // Gather media
        // Publish any media that has been published before (so it maintains its path). Ignore all else
        KTPage *homePage = [[self site] rootPage];
        [homePage publish:self recursively:YES];
        
        
        // Now have most dependencies in place, so can publish for real after that
        [[KTImageScalingURLProtocol coreImageQueue] addOperation:nextOp];
        [nextOp release];
    }
}

- (void)mainPublishing
{
    if (![NSThread isMainThread])
    {
        return [[self ks_proxyOnThread:nil waitUntilDone:NO] mainPublishing];
    }
    
    LOG((@"Phase two of publishing!"));
    
    
    // Store the op ready for dependencies to be added
    NSOperation *nextOp = [[NSInvocationOperation alloc]
                                     initWithTarget:self
                                     selector:@selector(finishPublishing)
                                     object:nil];
    
    [self setStartNextPhaseOperation:nextOp];
    
    
    // Publish pages properly
    _status = KTPublishingEngineStatusParsing;
    [self setCountOfPublishedItems:0];  // reset
    KTPage *home = [[self site] rootPage];
    [home publish:self recursively:YES];
    
    
    // Publish design
    [self publishDesign];
    
    
    
    // Once all is done (the op should now have most dependencies it needs), finish up
    [[KTImageScalingURLProtocol coreImageQueue] addOperation:nextOp];
    [nextOp release];
}

- (void)cancel
{
    [super cancel]; // so -isCancelled returns YES
    
    // Cancel any in-progress operations
    [[[self startNextPhaseOperation] dependencies] makeObjectsPerformSelector:_cmd];
    
    // Mark self as finished
    if ([self status] > KTPublishingEngineStatusNotStarted && [self status] < KTPublishingEngineStatusFinished)
    {
        [self engineDidPublish:NO error:[NSError errorWithDomain:NSCocoaErrorDomain code:NSUserCancelledError userInfo:nil]];
    }
}

#pragma mark Counting Published Items

@synthesize countOfPublishedItems = _countOfPublishedItems;

- (NSUInteger)incrementingCountOfPublishedItems;
{
	return ++_countOfPublishedItems;
}

- (KTPublishingEngineStatus)status { return _status; }

@synthesize startNextPhaseOperation = _nextOp;

- (void)addOperation:(NSOperation *)operation queue:(NSOperationQueue *)queue;
{
    [[self startNextPhaseOperation] addDependency:operation];
    
    if (!queue)
    {
        if ([NSOperationQueue respondsToSelector:@selector(mainQueue)])
        {
            queue = [NSOperationQueue mainQueue];
        }
        else
        {
            queue = [self defaultQueue];
        }
    }
    
    OBASSERT(queue);
    [queue addOperation:operation];
}

- (NSOperationQueue *)diskOperationQueue; { return _diskQueue; }

#pragma mark Transfer Records

- (CKTransferRecord *)rootTransferRecord { return _rootTransferRecord; }

/*  Also has the side-effect of updating the base transfer record
 */
- (void)setRootTransferRecord:(CKTransferRecord *)rootRecord
{
    [rootRecord retain];
    [_rootTransferRecord release];
    _rootTransferRecord = rootRecord;
    
    // If there is a subfolder, create it. This also gives us a valid -baseTransferRecord
    [self willChangeValueForKey:@"baseTransferRecord"]; // Automatic KVO-notifications are used for rootTransferRecord
    [_baseTransferRecord release];
    _baseTransferRecord = (rootRecord) ? [[self createDirectory:[self baseRemotePath]] retain] : nil;
    [self didChangeValueForKey:@"baseTransferRecord"];
}

/*  The transfer record corresponding to -baseRemotePath. There is no decdicated setter method, use
 *  -setRootTransferRecord: instead to generate a new baseTransferRecord.
 */
- (CKTransferRecord *)baseTransferRecord
{
   return _baseTransferRecord;
}

#pragma mark Publishing

- (SVHTMLContext *)beginPublishingHTMLToPath:(NSString *)path;
{
    // Don't let data be published twice
    NSString *fullPath = [[self baseRemotePath] stringByAppendingPathComponent:path];
    
    if ([self isPublishingToPath:fullPath])
    {
        path = nil;
    }
    
    // Make context
    SVPublishingHTMLContext *result = [[SVPublishingHTMLContext alloc] initWithUploadPath:path
                                                                                publisher:self];
    
    return [result autorelease];
}

/*	Use these methods instead of asking the connection directly. They will handle creating the
 *  appropriate directories first if needed.
 */
- (void)publishContentsOfURL:(NSURL *)localURL toPath:(NSString *)remotePath
{
	[self publishContentsOfURL:localURL toPath:remotePath cachedSHA1Digest:nil object:nil];
}

- (void)publishContentsOfURL:(NSURL *)localURL
                      toPath:(NSString *)remotePath
            cachedSHA1Digest:(NSData *)digest  // save engine the trouble of calculating itself
                      object:(id <SVPublishedObject>)object;
{
    OBPRECONDITION(localURL);
    OBPRECONDITION(remotePath);
    
    if ([self isPublishingToPath:remotePath]) return;
    
    
    // Non-file URLs need to be uploaded as data
    if (![localURL isFileURL])
    {
        // Ideally this code should be async to improve performance. But right now we're only using it to load banner, which is likely cached, so should be fast enough.
        NSData *data = [NSURLConnection sendSynchronousRequest:[NSURLRequest requestWithURL:localURL]
                                             returningResponse:NULL
                                                         error:NULL];
        
        if (data) [self publishData:data toPath:remotePath];
        return;
    }
    
    
    BOOL isDirectory = NO;
    if ([[NSFileManager defaultManager] fileExistsAtPath:[localURL path] isDirectory:&isDirectory])
    {
        // Is the URL actually a directory? If so, upload its contents
        if (isDirectory)
        {
            NSArray *subpaths = [[NSFileManager defaultManager] directoryContentsAtPath:[localURL path]];
            NSString *aSubPath;
            for (aSubPath in subpaths)
            {
                NSURL *aURL = [localURL ks_URLByAppendingPathComponent:aSubPath isDirectory:NO];
                NSString *aRemotePath = [remotePath stringByAppendingPathComponent:aSubPath];
                [self publishContentsOfURL:aURL toPath:aRemotePath];
            }
        }
        else
        {
            CKTransferRecord *result = [self uploadContentsOfURL:localURL toPath:remotePath];
            [self didEnqueueUpload:result toPath:remotePath cachedSHA1Digest:digest contentHash:nil object:object];
        }
    }
    else
    {
        NSLog(@"Not uploading contents of %@ as it does not exist", [localURL path]);
    }
}

- (void)publishData:(NSData *)data toPath:(NSString *)uploadPath;
{
    [self publishData:data toPath:uploadPath cachedSHA1Digest:nil contentHash:nil mediaRequest:nil object:nil];
}

- (void)publishData:(NSData *)data
             toPath:(NSString *)remotePath
   cachedSHA1Digest:(NSData *)digest                // save engine the trouble of calculating itself
        contentHash:(NSData *)hash
       mediaRequest:(SVMediaRequest *)mediaRequest  // if there was one behind all this
             object:(id <SVPublishedObject>)object;
{
	OBPRECONDITION(remotePath);
    
    if ([self isPublishingToPath:remotePath])
    {
        // Make sure contentHash of transfer record is up to date
        CKTransferRecord *record = [CKTransferRecord recordForFullPath:remotePath withRoot:[self rootTransferRecord]];
        
        [self didEnqueueUpload:record
                        toPath:remotePath
              cachedSHA1Digest:digest
                   contentHash:hash
                        object:object];
        
        return;
    }
    
	OBPRECONDITION(data);
    
    CKTransferRecord *result = [self uploadData:data toPath:remotePath];
    
    if (result)
    {
        [self didEnqueueUpload:result
                        toPath:remotePath
              cachedSHA1Digest:digest
                   contentHash:hash
                        object:object];
    }
}
    
- (BOOL)isPublishingToPath:(NSString *)path;
{
    BOOL result = [[self digestStorage] containsPath:path];
    return result;
}

- (CKTransferRecord *)uploadContentsOfURL:(NSURL *)localURL toPath:(NSString *)remotePath
{
    CKTransferRecord *result = nil;
    
    CKTransferRecord *parent = [self willUploadToPath:remotePath];
    
    // Need to use -setName: otherwise the record will have the full path as its name            
    id <CKConnection> connection = [self connection];
    //OBASSERT(connection); // actually if there's no connection, can't publish, so return nil. Up to client to handle
    
    if (connection)
    {
        [connection connect];	// Ensure we're connected
        
        result = [connection uploadFile:[localURL path]
                                                   toFile:remotePath
                                     checkRemoteExistence:NO
                                                 delegate:nil];
        
        [result setName:[remotePath lastPathComponent]];
        
        [self didEnqueueUpload:result toDirectory:parent];
    }
    
    return result;
}

/*  Raw, get me some stuff on the server!
 */
- (CKTransferRecord *)uploadData:(NSData *)data toPath:(NSString *)remotePath;
{
    CKTransferRecord *result = nil;
    
    CKTransferRecord *parent = [self willUploadToPath:remotePath];
    
    id <CKConnection> connection = [self connection];
    //OBASSERT(connection); // actually if there's no connection, can't publish, so return nil. Up to client to handle
    
    if (connection)
    {
        [connection connect];	// ensure we're connected
        
        result = [connection uploadFromData:data toFile:remotePath checkRemoteExistence:NO delegate:nil];
        OBASSERT(result);
        
        [result setName:[remotePath lastPathComponent]];
        
        if (result)
        {
            [self didEnqueueUpload:result toDirectory:parent];
        }
        else
        {
            NSLog(@"Unable to create transfer record for path:%@ data:%@", remotePath, data); // case 40520 logging
        }
    }
    
    return result;
}

- (CKTransferRecord *)willUploadToPath:(NSString *)path;
{
    CKTransferRecord *parent = [self createDirectory:[path stringByDeletingLastPathComponent]];
    return parent;
}

- (void)didEnqueueUpload:(CKTransferRecord *)record
                  toPath:(NSString *)path
        cachedSHA1Digest:(NSData *)digest
             contentHash:(NSData *)contentHash
                  object:(id <SVPublishedObject>)object;
{
    [[self digestStorage] addPath:path digest:digest];
}

- (void)didEnqueueUpload:(CKTransferRecord *)record toDirectory:(CKTransferRecord *)parent;
{
    [parent addContent:record];
    
    NSString *path = [record path];
    [[self connection] setPermissions:[self remoteFilePermissions]
                              forFile:path];
}

#pragma mark CSS

- (void)addCSSString:(NSString *)css;
{
    if (![_plugInCSS containsObject:css]) [_plugInCSS addObject:css];
}

- (void)addCSSWithURL:(NSURL *)cssURL;
{
    cssURL = [cssURL absoluteURL];
    if (![_plugInCSS containsObject:cssURL]) [_plugInCSS addObject:cssURL];
}

#pragma mark Design

- (NSString *)designDirectoryPath;
{
    KTDesign *design = [[[[self site] rootPage] master] design];
    NSString *result = [[self baseRemotePath] stringByAppendingPathComponent:[design remotePath]];
    return result;
}

- (void)publishDesign;
{
    KTPage *rootPage = [[self site] rootPage];
    KTMaster *master = [rootPage master];
    KTDesign *design = [master design];
    
    SVPublishingHTMLContext *context = [[SVPublishingHTMLContext alloc] initWithUploadPath:nil publisher:self];
    [context performSelector:@selector(startDocumentWithPage:) withObject:rootPage];   // HACK way to set .page so that CSS can be located properly
    
    
    [master writeCSS:context];
    [context release];
    
    NSString *remoteDesignDirectoryPath = [self designDirectoryPath];
    
    // Upload the design's resources
	for (NSURL *aResource in [design resourceFileURLs])
	{
		NSString *filename = [aResource ks_lastPathComponent];
        NSString *uploadPath = [remoteDesignDirectoryPath stringByAppendingPathComponent:filename];
        
        if ([filename isEqualToString:@"main.css"])
        {
            [self publishMainCSSToPath:uploadPath];
        }
        else
        {
            [self publishContentsOfURL:aResource toPath:uploadPath];
        }
	}
}

/*  KTRemotePublishingEngine uses digest to only upload this if it's changed
 */
- (void)publishMainCSSToPath:(NSString *)cssUploadPath;
{
    NSMutableString *css = [NSMutableString string];
    KSCSSWriter *cssWriter = [[KSCSSWriter alloc] initWithOutputWriter:css];
    
    
    // Write CSS
    for (id someCSS in _plugInCSS)
    {
        if ([someCSS isKindOfClass:[NSURL class]])
        {
            NSString *cssFromURL = [NSString stringWithContentsOfURL:someCSS
													fallbackEncoding:NSUTF8StringEncoding
															   error:NULL];
            
            if (cssFromURL)
			{
#ifndef VARIANT_RELEASE
				[cssWriter writeCSSString:
				 [NSString stringWithFormat:@"/* ----------- Source: %@ ----------- */",
				  [[someCSS path] lastPathComponent]]];
#endif
				[cssWriter writeCSSString:cssFromURL];

#ifndef VARIANT_RELEASE
				[cssWriter writeCSSString:
				 [NSString stringWithFormat:@"/* ----------- End:    %@ ----------- */",
				  [[someCSS path] lastPathComponent]]];
#endif
			}
        }
        else
        {
            [cssWriter writeCSSString:someCSS];
        }
    }
    
    [cssWriter release];
    
    
    
    // Upload the CSS if needed
    NSData *mainCSSData = [[css unicodeNormalizedString] dataUsingEncoding:NSUTF8StringEncoding
                                                      allowLossyConversion:YES];
    
    [self publishData:mainCSSData toPath:cssUploadPath];
}

- (void)addDependencyOnObject:(NSObject *)object keyPath:(NSString *)keyPath { }

#pragma mark Media

- (NSString *)startPublishingMedia:(SVMediaRequest *)request cachedSHA1Digest:(NSData *)cachedDigest;
{
    OBPRECONDITION(request);
    
    
    [_digestStorage addMediaRequest:request cachedDigest:cachedDigest];
    
    
    // Do the calculation on a background thread. Which one depends on the task needed
    if ([request isNativeRepresentation])
    {
        NSData *data = [[request media] mediaData];
        if (data)
        {
            // This point shouldn't logically be reached if hash is already known, so it just needs hashing on a CPU-bound queue
            NSInvocation *invocation = [NSInvocation
                                        invocationWithSelector:@selector(threaded_publishData:forMedia:)
                                        target:self
                                        arguments:NSARRAY(data, request)];
            
            NSInvocationOperation *op = [[NSInvocationOperation alloc] initWithInvocation:invocation];
            [[self digestStorage] setHashingOperation:op forMediaRequest:request];
            [self addOperation:op queue:[self defaultQueue]];
            [op release];
        }
        else
        {
            // Read data from disk for hashing
            NSInvocation *invocation = [NSInvocation
                                        invocationWithSelector:@selector(threaded_publishMedia:cachedSHA1Digest:)
                                        target:self
                                        arguments:NSARRAY(request, cachedDigest)];
            
            NSInvocationOperation *op = [[NSInvocationOperation alloc] initWithInvocation:invocation];
            [[self digestStorage] setHashingOperation:op forMediaRequest:request];
            [self addOperation:op queue:_diskQueue];
            [op release];
        }
    }
    else
    {
        // Already been cached?
        NSData *data = [[self digestStorage] dataForMediaRequest:request];
        if (!data)
        {
            NSURL *URL = [NSURL sandvoxImageURLWithMediaRequest:request];
            data = [[[NSURLCache sharedURLCache] cachedResponseForRequest:[NSURLRequest requestWithURL:URL]] data];
        }
        
        if (data)
        {
            // It's cached! Just need to calculate the hash which is pretty speedy            
            return [self publishMediaWithRequest:request cachedData:data SHA1Digest:[data SHA1Digest]];
        }
        else
        {
            NSInvocation *invocation = [NSInvocation
                                        invocationWithSelector:@selector(threaded_publishMedia:cachedSHA1Digest:)
                                        target:self
                                        arguments:NSARRAY(request, cachedDigest)];
            
            NSInvocationOperation *op = [[NSInvocationOperation alloc] initWithInvocation:invocation];
            [[self digestStorage] setHashingOperation:op forMediaRequest:request];
            [self addOperation:op queue:[KTImageScalingURLProtocol coreImageQueue]];  // most of the work should be Core Image's
            [op release];
        }
    }
    
    return nil;
}

- (NSString *)publishMediaWithRequest:(SVMediaRequest *)request cachedData:(NSData *)data SHA1Digest:(NSData *)digest
{
    OBPRECONDITION(request);
    OBPRECONDITION(digest);
    
    
    SVPublishingDigestStorage *digestStore = [self digestStorage];
    request = [digestStore addMediaRequest:request cachedDigest:digest];
    
    
    // Is there already an existing file on the server? If so, use that
    NSString *result = [self pathForFileWithSHA1Digest:digest];
    if (!result)
    {
        NSData *sourceDigest = [digestStore digestForMediaRequest:[request sourceRequest]]; 
        if (sourceDigest)
        {
            NSData *hash = [request contentHashWithMediaDigest:sourceDigest];
            if (hash)
            {
                result = [[self publishingRecordForContentHash:hash] path];
            }
        }
    }
    
    
    if (!result)
    {
        // Seek out a path not being published to
        result = [[self baseRemotePath] stringByAppendingPathComponent:[request preferredUploadPath]];
        
        while ([self isPublishingToPath:result])
        {
            result = [result ks_stringByIncrementingPath];
        }
        
        // During the first phase of publishing, want to avoid overwriting any existing media on the server
        if ([self status] <= KTPublishingEngineStatusGatheringMedia)
        {
            // This is new media. Is its preferred filename definitely available? If so, can go ahead and publish immediately. #111549. Otherwise, wait until all media is known to figure out the best available path
            if ([[[self site] hostProperties] publishingRecordForPath:result])
            {
                // but cache the data
                [digestStore addMediaRequest:request cachedDigest:digest];
                if (data) [digestStore setData:data forMediaRequest:request];
                result = nil;
            }
        }
    }
    
    
    // Publish!
    if (result)
    {
        // We might already know the data, ready to publish
        if (!data && [request isNativeRepresentation]) data = [[request media] mediaData];
        
        if (data)
        {
            NSData *hash = nil;
            NSData *sourceDigest = [digestStore digestForMediaRequest:[request sourceRequest]];
            
            if (sourceDigest)
            {
                hash = [request contentHashWithMediaDigest:sourceDigest];
            }
            
            [self publishData:data
                       toPath:result
             cachedSHA1Digest:digest
                  contentHash:hash
                 mediaRequest:request
                       object:nil];
        }
        else
        {
            if ([request isNativeRepresentation])
            {
                // Can publish the file itself
                [self publishContentsOfURL:[[request media] mediaURL]
                                    toPath:result
                          cachedSHA1Digest:digest
                                    object:nil];
            }
            else
            {
                // Fetching the data is potentially expensive, so do on worker thread again
                // No point if the publish will be rejected
                if (![self isPublishingToPath:result])
                {
                    [self startPublishingMedia:request cachedSHA1Digest:digest];
                }
                else
                {
                    // Make sure content hash is carried through
                    NSData *hash = nil;
                    NSData *sourceDigest = [digestStore digestForMediaRequest:[request sourceRequest]];
                    
                    if (sourceDigest)
                    {
                        hash = [request contentHashWithMediaDigest:sourceDigest];
                    }
                    
                    [self publishData:data
                               toPath:result
                     cachedSHA1Digest:digest
                          contentHash:hash
                         mediaRequest:request
                               object:nil];
                }
            }
        }
    }
    
    return result;
}

- (NSString *)publishMediaWithRequest:(SVMediaRequest *)request;
{
    NSString *result = nil;
    
    // During media gathering phase we want to:
    //  A)  Collect digests of all media (e.g. for dupe identification)
    //  B)  As a head start, queue for upload any media that has previously been published, thus reserving path
    
    if ([_digestStorage containsMediaRequest:request])
    {
        NSData *cachedDigest = [_digestStorage digestForMediaRequest:request];
        if (cachedDigest)  // nothing to do yet while hash is being calculated
        {
            result = [self publishMediaWithRequest:request cachedData:nil SHA1Digest:cachedDigest];
        }
    }
    else
    {
        // Calculating where to publish media is actually quite time-consuming, so do on a background thread
        result = [self startPublishingMedia:request cachedSHA1Digest:nil];
    }
    
    return result;
}

- (NSData *)threaded_publishMedia:(SVMediaRequest *)request cachedSHA1Digest:(NSData *)digest;
{
    /*  It is presumed that the call to this method will have been scheduled on an appropriate queue.
     */
    OBPRECONDITION(request);
    
    
    BOOL isNative = [request isNativeRepresentation];
    if (!isNative)
    {
        // Time to look closer to see if conversion/scaling is required
        CGImageSourceRef imageSource = IMB_CGImageSourceCreateWithImageItem((id)[request media], NULL);
        if (imageSource)
        {
            if ([[request type] isEqualToString:(NSString *)CGImageSourceGetType(imageSource)])
            {
                // TODO: Should we better take into account a source with multiple images?
                CFDictionaryRef properties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, NULL);
                if (properties)
                {
                    CFNumberRef width = CFDictionaryGetValue(properties, kCGImagePropertyPixelWidth);
                    CFNumberRef height = CFDictionaryGetValue(properties, kCGImagePropertyPixelHeight);
                    
                    if ([[request width] isEqualToNumber:(NSNumber *)width] &&
                        [[request height] isEqualToNumber:(NSNumber *)height])
                    {
                        isNative = YES;
                    }
                    
                    CFRelease(properties);
                }
            }
            
            CFRelease(imageSource);
        }
    }
    
    
    
    // Great! No messy scaling work to do!
    if (isNative)
    {
        SVMediaRequest *canonical = [[SVMediaRequest alloc] initWithMedia:[request media]
                                                      preferredUploadPath:[request preferredUploadPath]];
        OBASSERT([canonical isNativeRepresentation]);
        
        // Calculate hash
        // TODO: Ideally we could look up the canonical request to see if hash has already been generated (e.g. user opted to publish full-size copy of image too)
        if (!digest)
        {
            NSData *data = [[request media] mediaData];
            if (data)
            {
                digest = [data SHA1Digest];
            }
            else
            {
                NSURL *url = [[request media] mediaURL];
                digest = [NSData SHA1DigestOfContentsOfURL:url];
            
                if (!digest) NSLog(@"Unable to hash file: %@", url);
            }
        }
        
        if (digest)   // if couldn't be hashed, can't be published
        {
            // Publish original image first. Ensures the publishing of real request will be to the same path
            
            [[self ks_proxyOnThread:nil]  // wait until done so op isn't reported as finished too early
             publishMediaWithRequest:canonical cachedData:nil SHA1Digest:digest];
            
            [[self ks_proxyOnThread:nil]  // wait until done so op isn't reported as finished too early
             publishMediaWithRequest:request cachedData:nil SHA1Digest:digest];
        }
        
        [canonical release];
        return digest;
    }
    
    
    
    
    
    NSURLResponse *response;
    NSData *fileContents = [SVImageScalingOperation dataWithMediaRequest:request response:&response];
    
    if (fileContents)
    {
        // Since scaling was applied, we need to publish to the path requested. This should NOT affect equality of requests
        SVMediaRequest *original = request;
        request = [request requestWithScalingSuffixApplied];
        OBASSERT([request isEqualToMediaRequest:original]);
        
        if (digest)
        {
            // Hashing was done in a previous iteration, so recycle
            [[self ks_proxyOnThread:nil waitUntilDone:YES]  // wait before reporting op as finished
             publishMediaWithRequest:request cachedData:fileContents SHA1Digest:digest];
        }
        else
        {
            // Hash on a separate thread so this queue is ready to go again quickly
            NSInvocation *invocation = [NSInvocation
                                        invocationWithSelector:@selector(threaded_publishData:forMedia:)
                                        target:self
                                        arguments:[NSArray arrayWithObjects:fileContents, request, nil]];
            
            NSOperation *op = [[NSInvocationOperation alloc] initWithInvocation:invocation];
            [self addOperation:op queue:[self defaultQueue]];
            [op release];
        }
        
        
        // Cache the result
        if ([response URL])
        {
            NSCachedURLResponse *cachedResponse = [[NSCachedURLResponse alloc] initWithResponse:response
                                                                                           data:fileContents];
            
            [[NSURLCache sharedURLCache] storeCachedResponse:cachedResponse
                                                  forRequest:[NSURLRequest requestWithURL:[response URL]]];
            
            [cachedResponse release];
        }
    }
    else
    {
        NSLog(@"Unable to load media request: %@", request);
    }
    
    
    return digest;
}

- (NSData *)threaded_publishData:(NSData *)data forMedia:(SVMediaRequest *)request;
{
    /*  Since all that's needed is to hash the data, presumed you'll call this using -defaultQueue
     */
    OBPRECONDITION(data);
    OBPRECONDITION(request);
    
    NSData *digest = [data SHA1Digest];
    [[self ks_proxyOnThread:nil waitUntilDone:YES]  // wait before reporting op as finished
     publishMediaWithRequest:request cachedData:data SHA1Digest:digest];
    
    return digest;
}

#pragma mark Resource Files

- (NSString *)publishResourceAtURL:(NSURL *)fileURL;
{
    NSString *resourcesDirectoryName = [[NSUserDefaults standardUserDefaults] valueForKey:@"DefaultResourcesPath"];
    NSString *resourcesDirectoryPath = [[self baseRemotePath] stringByAppendingPathComponent:resourcesDirectoryName];
    NSString *resourceRemotePath = [resourcesDirectoryPath stringByAppendingPathComponent:[fileURL ks_lastPathComponent]];
    
    [self publishContentsOfURL:fileURL toPath:resourceRemotePath];
    
    return resourceRemotePath;
}

#pragma mark Publishing Records

- (NSString *)pathForFileWithSHA1Digest:(NSData *)digest;
{
    OBPRECONDITION(digest);
    
    NSString *result = [[self digestStorage] pathForFileWithDigest:digest];
    
    if (!result)
    {
        SVPublishingRecord *publishingRecord = [[[self site] hostProperties]
                                                publishingRecordForSHA1Digest:digest];
        
        NSString *publishedPath = [publishingRecord path];
        if (publishedPath)
        {
            // The record's path is for the published site. Correct to account for current pub location
            
            KTHostProperties *hostProperties = [[self site] hostProperties];
            NSString *base = [[hostProperties documentRoot]
                              stringByAppendingPathComponent:[hostProperties subfolder]];
            
            NSString *relativePath = [publishedPath ks_pathRelativeToDirectory:base];
            result = [[self baseRemotePath] stringByAppendingPathComponent:relativePath];
        }
    }
    
    return result;
}

- (SVPublishingRecord *)publishingRecordForContentHash:(NSData *)digest;
{
    return [_publishingRecordsByContentHash objectForKey:digest];
}

- (void)setContentHash:(NSData *)hash forPublishingRecord:(SVPublishingRecord *)record;
{
    NSData *oldHash = [record contentHash];
    if (!KSISEQUAL(hash, oldHash))
    {
        if (oldHash) [_publishingRecordsByContentHash removeObjectForKey:oldHash];
        
        [record setContentHash:hash];
        if (hash)
        {
            [_publishingRecordsByContentHash setObject:record forKey:hash];
        }
        else if (oldHash)
        {
            LOG((@"Nilled out content hash"));
        }
    }
}

#pragma mark Util

@synthesize defaultQueue = _defaultQueue;

@synthesize sitemapPinger = _sitemapPinger;

#pragma mark Delegate

- (id <KTPublishingEngineDelegate>)delegate { return _delegate; }

- (void)setDelegate:(id <KTPublishingEngineDelegate>)delegate { _delegate = delegate; }

@end


#pragma mark -


@implementation KTPublishingEngine (SubclassSupport)

#pragma mark Overall flow control

/*  Call this method once publishing has ended, whether it be successfully or not.
 *  This method is responsible for cleaning up after publishing, and informing the delegate.
 */
- (void)engineDidPublish:(BOOL)didPublish error:(NSError *)error
{
    OBPRECONDITION([self status] > KTPublishingEngineStatusNotStarted && [self status] < KTPublishingEngineStatusFinished);
    
    
    // In the event of failure, end page parsing and media URL connections
    if (!didPublish)
    {
        [NSObject cancelPreviousPerformRequestsWithTarget:self];
        
        // Disconnect connection
        [[self connection] forceDisconnect];
    }
    
    
    
    _status = KTPublishingEngineStatusFinished;
    
    [self setConnection:nil];
    
    
    // Inform the delegate
    if (didPublish)
    {
        [[self delegate] publishingEngineDidFinish:self];
    }
    else
    {
        [[self delegate] publishingEngine:self didFailWithError:error];
    }
}

#pragma mark Connection

/*  Simple accessor for the connection. If we haven't started uploading yet, or have finished, it returns nil.
 *  The -connect method is responsible for creating and storing the connection.
 */
- (id <CKConnection>)connection { return _connection; }

- (void)setConnection:(id <CKConnection>)connection
{
    [connection retain];
	
	[_connection setDelegate:nil];
	[_connection release];
	_connection = connection;
    
	[connection setDelegate:self];
}

/*  Subclasses should override to create a connection and call -setConection: with it. By default we use a file connection
 */
- (void)createConnection
{
    id <CKConnection> result = [[CKFileConnection alloc] init];
    OBASSERT(result);
    [self setConnection:result];
	[result release];
}

/*  Exporting shouldn't require any authentication
 */
- (void)connection:(id <CKConnection>)connection didReceiveAuthenticationChallenge:(NSURLAuthenticationChallenge *)challenge;
{
    [[challenge sender] continueWithoutCredentialForAuthenticationChallenge:challenge];
}

/*	Just pass on a simplified version of these 2 messages to our delegate
 */
- (void)connection:(id <CKConnection>)con uploadDidBegin:(NSString *)remotePath;
{
	[[self delegate] publishingEngine:self didBeginUploadToPath:remotePath];
}

- (void)connection:(id <CKConnection>)con upload:(NSString *)remotePath progressedTo:(NSNumber *)percent;
{
    if ([self status] <= KTPublishingEngineStatusUploading)
    {
        [[self delegate] publishingEngineDidUpdateProgress:self];
    }
}

- (void)connection:(id <CKConnection>)con didDisconnectFromHost:(NSString *)host;
{
    if (![self connection]) return; // we've already finished in which case
    
    OBPRECONDITION(con == [self connection]);
    OBPRECONDITION(con);
    
    
    // Case 39234: It looks like ConnectionKit is sending this delegate method in the event of the
    // data connection closing (or it might even be the command connection), probably due to a
    // period of inactivity. In such a case, it's really not a cause to consider publishing
    // finished! To see if I am right on this, we will log that such a scenario occurred for now.
    // Mike.
    
    if ([self status] == KTPublishingEngineStatusUploading &&
        ![con isConnected] &&
        [[(CKAbstractQueueConnection *)con commandQueue] count] == 0)
    {
        [self engineDidPublish:YES error:nil];
    }
    else
    {
        NSLog(@"%@ delegate method received, but connection still appears to be publishing", NSStringFromSelector(_cmd));
    }
}

/*  We either ignore the error and continue or fail and inform the delegate
 */
- (void)connection:(id <CKConnection>)con didReceiveError:(NSError *)error;
{
    if (con != [self connection]) return;
    
    
    
    if ([[error userInfo] objectForKey:ConnectionDirectoryExistsKey]) 
	{
		return; //don't alert users to the fact it already exists, silently fail
	}
	else if ([error code] == 550 || [[[error userInfo] objectForKey:@"protocol"] isEqualToString:@"createDirectory:"] )
	{
		return;
	}
	else if ([con isKindOfClass:NSClassFromString(@"WebDAVConnection")] && 
			 ([[[error userInfo] objectForKey:@"directory"] isEqualToString:@"/"] || [error code] == 409 || [error code] == 204 || [error code] == 404))
	{
		// web dav returns a 409 if we try to create / .... which is fair enough!
		// web dav returns a 204 if a file to delete is missing.
		// 404 if the file to delete doesn't exist
		
		return;
	}
	else if ([error code] == kSetPermissions) // File connection set permissions failed ... ignore this (why?)
	{
		return;
	}
	else
	{
		[self engineDidPublish:NO error:error];
	}
}

- (void)connection:(id <CKConnection>)connection appendString:(NSString *)string toTranscript:(CKTranscriptType)transcript
{
	string = [string stringByAppendingString:@"\n"];
	NSAttributedString *attributedString = [[connection class] attributedStringForString:string transcript:transcript];
	[[[KTTranscriptController sharedControllerWithoutLoading] textStorage] appendAttributedString:attributedString];
}

#pragma mark Pages


/*  Uploads the site map if the site has the option enabled
 */
- (void)uploadGoogleSiteMapIfNeeded
{
    if ([[self site] boolForKey:@"generateGoogleSitemap"])
    {
        NSString *sitemapXML = [[self site] googleSiteMapXMLString];
        NSData *siteMapData = [sitemapXML dataUsingEncoding:NSUTF8StringEncoding allowLossyConversion:YES];
        NSData *gzipped = [siteMapData compressGzip];
        
        NSString *siteMapPath = [[self baseRemotePath] stringByAppendingPathComponent:@"sitemap.xml.gz"];
        self.sitemapPinger = [[[SVGoogleSitemapPinger alloc] init] autorelease];
        
        [self publishData:gzipped
                   toPath:siteMapPath
         cachedSHA1Digest:nil
              contentHash:nil
             mediaRequest:nil
                   object:self.sitemapPinger];
    }
}

- (void)finishPublishing;
{
    if (![NSThread isMainThread])
    {
        return [[self ks_proxyOnThread:nil] finishPublishing];
    }
    
    // Upload sitemap if the site has one
    [self uploadGoogleSiteMapIfNeeded];
    
    
    // Inform the delegate if there's no pending media. If there is, we'll inform once that is done
    _status = KTPublishingEngineStatusUploading;
    [[self delegate] publishingEngineDidFinishGeneratingContent:self];
    
    
    // Once everything is uploaded, disconnect. May be that nothing was published, so end immediately
    [[self connection] disconnect];
    if (![[[self baseTransferRecord] contents] count]) [self engineDidPublish:YES error:NULL];
}

#pragma mark Uploading Support

/*  Creates the specified directory including any parent directories that haven't already been queued for creation.
 *  Returns a CKTransferRecord used to represent the directory during publishing.
 */
- (CKTransferRecord *)createDirectory:(NSString *)remotePath
{
    OBPRECONDITION(remotePath);
    
    
    if ([remotePath isEqualToString:@"/"] || [remotePath isEqualToString:@""]) // The root for absolute and relative paths
    {
        return [self rootTransferRecord];
    }
    
    
    // Ensure the parent directory is created first
    NSString *parentDirectoryPath = [remotePath stringByDeletingLastPathComponent];
    OBASSERT(![parentDirectoryPath isEqualToString:[remotePath ks_standardizedPOSIXPath]]);
    CKTransferRecord *parent = [self createDirectory:parentDirectoryPath];
    
    
    // Create the directory if it hasn't been already
    CKTransferRecord *result = nil;
    int i;
    for (i = 0; i < [[parent contents] count]; i++)
    {
        CKTransferRecord *aRecord = [[parent contents] objectAtIndex:i];
        if ([[aRecord name] isEqualToString:[remotePath lastPathComponent]])
        {
            result = aRecord;
            break;
        }
    }
    
    if (!result)
    {
        // This code will not set permissions for the document root or its parent directories as the
        // document root is created before this code gets called
        [[self connection] createDirectory:remotePath permissions:[self remoteDirectoryPermissions]];
        result = [CKTransferRecord recordWithName:[remotePath lastPathComponent] size:0];
        [parent addContent:result];
    }
    
    return result;
}

/*  The POSIX permissions that should be applied to files and folders on the server.
 */

- (unsigned long)remoteFilePermissions
{
    unsigned long result = 0;
    
    NSString *perms = [[NSUserDefaults standardUserDefaults] stringForKey:@"pagePermissions"];
    if (perms)
    {
        if (![perms hasPrefix:@"0"])
        {
            perms = [NSString stringWithFormat:@"0%@", perms];
        }
        char *num = (char *)[perms UTF8String];
        unsigned int p;
        sscanf(num,"%o",&p);
        result = p;
    }
    
    // Fall back
    if (result == 0)
    {
        result = 0644;
    }
    
    
    return result;
}

- (unsigned long)remoteDirectoryPermissions
{
    unsigned long result = ([self remoteFilePermissions] | 0111);
    return result;
}

@end

