//
//  SVMediaGatheringPublishingContext.m
//  Sandvox
//
//  Created by Mike on 14/04/2010.
//  Copyright 2010 Karelia Software. All rights reserved.
//

#import "SVMediaGatheringPublisher.h"

#import "SVMediaGatheringHTMLContext.h"


@implementation SVMediaGatheringPublisher

- (id)init
{
    [super init];
    
    _context = [[SVMediaGatheringHTMLContext alloc] initWithUploadPath:nil publisher:self];
    
    return self;
}

- (void)dealloc;
{
    [_context release];
    [super dealloc];
}

@synthesize publishingEngine = _mediaPublisher;

/*  Ignore most publishing commands */
- (void)publishData:(NSData *)data toPath:(NSString *)remotePath;
{
    [self publishData:data toPath:remotePath cachedSHA1Digest:nil contentHash:nil object:nil];
}
- (void)publishContentsOfURL:(NSURL *)localURL toPath:(NSString *)remotePath
{
    [self publishContentsOfURL:localURL toPath:remotePath cachedSHA1Digest:nil object:nil];
}

- (void)publishData:(NSData *)data
             toPath:(NSString *)remotePath
   cachedSHA1Digest:(NSData *)digest  // save engine the trouble of calculating itself
        contentHash:(NSData *)hash
             object:(id <SVPublishedObject>)object;
{
}

- (void)publishContentsOfURL:(NSURL *)localURL
                      toPath:(NSString *)remotePath
            cachedSHA1Digest:(NSData *)digest  // save engine the trouble of calculating itself
                      object:(id <SVPublishedObject>)object;
{
}

- (NSString *)publishResourceAtURL:(NSURL *)fileURL;
{
    return nil;
}

- (SVHTMLContext *)beginPublishingHTMLToPath:(NSString *)path
{
    return _context;
}

- (NSString *)publishMedia:(id <SVMedia>)mediaRep;
{
    return [[self publishingEngine] publishMedia:mediaRep];
}

- (void)addCSSString:(NSString *)css; { }
- (void)addCSSWithURL:(NSURL *)cssURL; { }

- (NSString *)baseRemotePath; { return [[self publishingEngine] baseRemotePath]; }

- (NSString *)designDirectoryPath; { return nil; }

@end
