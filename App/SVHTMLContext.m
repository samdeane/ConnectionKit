//
//  SVHTMLContext.m
//  Sandvox
//
//  Created by Mike on 19/10/2009.
//  Copyright 2009 Karelia Software. All rights reserved.
//

#import "SVWebEditorHTMLContext.h"

#import "KTDesign.h"
#import "SVGraphic.h"
#import "KTHostProperties.h"
#import "SVHTMLTemplateParser.h"
#import "SVHTMLTextBlock.h"
#import "KTMaster.h"
#import "SVMediaRecord.h"
#import "KTPage.h"
#import "KTSite.h"
#import "SVTemplate.h"
#import "SVTextAttachment.h"
#import "Registration.h"

#import "SVCalloutDOMController.h"  // don't like having to do this

#import "BDAlias+QuickLook.h"

#import "NSIndexPath+Karelia.h"
#import "NSString+Karelia.h"
#import "NSURL+Karelia.h"


@interface SVHTMLIterator : NSObject
{
    NSUInteger  _iteration;
    NSUInteger  _count;
}

- (id)initWithCount:(NSUInteger)count;
@property(nonatomic, readonly) NSUInteger count;

@property(nonatomic, readonly) NSUInteger iteration;
- (NSUInteger)nextIteration;

@end


@interface SVHTMLContext ()
- (void)endCallout;
- (SVHTMLIterator *)currentIterator;
@end


#pragma mark -


@implementation SVHTMLContext

#pragma mark Init & Dealloc

- (id)initWithOutputWriter:(id <KSWriter>)output; // designated initializer
{
    // One buffer to hold page markup until we have collected all head info
    _postHeaderBuffer = [[KSMegaBufferedWriter alloc] initWithOutputWriter:output];
    
    // And another buffer for grouping callouts
    _calloutBuffer = [[KSMegaBufferedWriter alloc] initWithOutputWriter:_postHeaderBuffer];
    [_calloutBuffer setDelegate:self];
    
    
    [super initWithOutputWriter:_calloutBuffer];
    
    
    _includeStyling = YES;
    _mainCSS = [[NSMutableString alloc] init];
    
    _liveDataFeeds = YES;
    [self setEncoding:NSUTF8StringEncoding];
    
    _docType = KTXHTMLTransitionalDocType;
    _maxDocType = NSIntegerMax;
    
    _headerLevel = 1;
    _headerMarkup = [[NSMutableString alloc] init];
    _endBodyMarkup = [[NSMutableString alloc] init];
    _iteratorsStack = [[NSMutableArray alloc] init];
    
    return self;
}

- (id)initWithMutableString:(NSMutableString *)output;
{
    if (self = [self initWithOutputWriter:output])
    {
        _output = [output retain];
    }
    
    return self;
}

- (id)init;
{
    NSMutableString *output = [[NSMutableString alloc] init];
    self = [self initWithMutableString:output];
    [output release];
    return self;
}

- (void)dealloc
{
    [_language release];
    [_baseURL release];
    [_currentPage release];
    
    [_mainCSSURL release];
    [_mainCSS release];
    
    [_headerMarkup release];
    [_endBodyMarkup release];
    [_iteratorsStack release];
    
    [super dealloc];
    
    OBASSERT(!_postHeaderBuffer);   // super should have called -close to set this to nil
    OBASSERT(!_calloutBuffer);
    OBASSERT(!_output);
}

#pragma mark Status

- (void)reset;
{
    [[self mutableString] setString:@""];
}

#pragma mark Document

- (void)startDocumentWithPage:(KTPage *)page
{
    OBPRECONDITION(page);
    
	// Prepare global properties
    [self setEncoding:[[[page master] valueForKey:@"charset"] encodingFromCharset]];
    [self setLanguage:[[page master] language]];
    
    NSString *cssPath = [page pathToDesignFile:@"main.css" inContext:self];
    [self setMainCSSURL:[NSURL URLWithString:cssPath
                               relativeToURL:[self baseURL]]];
    
    
    
    // Global CSS
    NSString *path = [[NSBundle mainBundle] pathForResource:@"sandvox" ofType:@"css"];
    NSString *contents = [NSString stringWithContentsOfFile:path
                                                   encoding:NSUTF8StringEncoding
                                                      error:NULL];
    if (contents) [[self mainCSS] appendString:contents];
    
	
    
    
    // First Code Injection
	[page writeCodeInjectionBeforeHTML];
    
    
    // Start the document
    KTDocType docType = [self docType];
    [self startDocument:[[self class] stringFromDocType:docType]
                isXHTML:(docType >= KTXHTMLTransitionalDocType)];
    
}

- (void)writeDocumentWithPage:(KTPage *)page;
{
    [self startDocumentWithPage:page];

    
    // It's template time!
	SVHTMLTemplateParser *parser = [[SVHTMLTemplateParser alloc] initWithPage:page];
    [parser parseIntoHTMLContext:self];
    [parser release];
    
    
    // Now, did that change the doctype? Retry if possible!
    if (_maxDocType > KTHTML5DocType) _maxDocType = KTXHTMLTransitionalDocType;
    if (_maxDocType != [self docType])
    {
        if ([self mutableString])
        {
            [self reset];
            [self setDocType:_maxDocType];
            [self writeDocumentWithPage:page];
        }
    }
	
    // Load up main.css from the DESIGN, which might override the generic stuff
	NSString *mainCSS = [NSString stringWithData:[[[page master] design] mainCSSData]
                                        encoding:NSUTF8StringEncoding];
    if (mainCSS) [[self mainCSS] appendString:mainCSS];
    
	
	// For preview/quicklook mode, the banner CSS (after the design's main.css)
    [[page master] writeBannerCSS:self];
	
    
	// If we're for editing, include additional editing CSS
	if ([self isForEditing])
	{
		NSString *editingCSSPath = [[NSBundle mainBundle] pathForResource:@"design-time"
                                                                   ofType:@"css"];
        NSString *editingCSS = [NSString stringWithContentsOfFile:editingCSSPath
                                                         encoding:NSUTF8StringEncoding
                                                            error:NULL];
		if (editingCSS) [[self mainCSS] appendString:editingCSS];
	}
}


#pragma mark Properties

@synthesize mutableString = _output;

@synthesize baseURL = _baseURL;
@synthesize liveDataFeeds = _liveDataFeeds;
@synthesize encoding = _stringEncoding;
@synthesize language = _language;

- (void)copyPropertiesFromContext:(SVHTMLContext *)context;
{
    // Copy across properties
    [self setIndentationLevel:[context indentationLevel]];
    [self setPage:[context page]];
    [self setBaseURL:[context baseURL]];
    [self setIncludeStyling:[context includeStyling]];
    [self setLiveDataFeeds:[context liveDataFeeds]];
    [self setDocType:[context docType]];
    [self setEncoding:[context encoding]];
}

#pragma mark Doctype

@synthesize docType = _docType;

- (void)limitToMaxDocType:(KTDocType)docType;
{
    if (docType < _maxDocType) _maxDocType = docType;
}

+ (NSString *)titleOfDocType:(KTDocType)docType  localize:(BOOL)shouldLocalizeForDisplay;
{
	NSString *result = nil;
	NSString *localizedResult = nil;
	switch (docType)
	{
		case KTHTML401DocType:
			result = @"HTML 4.01 Transitional";
			localizedResult = NSLocalizedString(@"HTML 4.01", @"Description of style of HTML - note that we do not say Transitional");
			break;
		case KTXHTMLTransitionalDocType:
			result = @"XHTML 1.0 Transitional";
			localizedResult = NSLocalizedString(@"XHTML 1.0 Transitional", @"Description of style of HTML");
			break;
		case KTXHTMLStrictDocType:
			result = @"XHTML 1.0 Strict";
			localizedResult = NSLocalizedString(@"XHTML 1.0 Strict", @"Description of style of HTML");
			break;
		case KTHTML5DocType:
			result = @"HTML5";
			localizedResult = NSLocalizedString(@"HTML5", @"Description of style of HTML");
			break;
		default:
			break;
	}
	return shouldLocalizeForDisplay ? localizedResult : result;
}

+ (NSString *)stringFromDocType:(KTDocType)docType;
{
    NSString *result = nil;
	
    switch (docType)
    {
        case KTHTML401DocType:
            result = @"<!DOCTYPE HTML PUBLIC \"-//W3C//DTD HTML 4.01 Transitional//EN\" \"http://www.w3.org/TR/html4/loose.dtd\">";
            break;
        case KTXHTMLTransitionalDocType:
            result = @"<!DOCTYPE html PUBLIC \"-//W3C//DTD XHTML 1.0 Transitional//EN\" \"http://www.w3.org/TR/xhtml1/DTD/xhtml1-transitional.dtd\">";
            break;
        case KTXHTMLStrictDocType:
            result = @"<!DOCTYPE html PUBLIC \"-//W3C//DTD XHTML 1.0 Strict//EN\" \"http://www.w3.org/TR/xhtml1/DTD/xhtml1-strict.dtd\">";
            break;
        case KTHTML5DocType:
            result = [NSString stringWithFormat:@"<!DOCTYPE html>"];
            break;
        default:
            break;
    }
    
    return result;
}

#pragma mark Purpose

- (KTHTMLGenerationPurpose)generationPurpose; { return kSVHTMLGenerationPurposeNormal; }

- (BOOL)isForEditing; { return [self generationPurpose] == kSVHTMLGenerationPurposeEditing; }

- (BOOL)isEditable { return [self isForEditing]; }  // left in for compat. for now
+ (NSSet *)keyPathsForValuesAffectingEditable
{
    return [NSSet setWithObject:@"generationPurpose"];
}

- (BOOL)isForQuickLookPreview;
{
    BOOL result = [self generationPurpose] == kSVHTMLGenerationPurposeQuickLookPreview;
    return result;
}

- (BOOL)isForPublishing
{
    BOOL result = [self generationPurpose] == kSVHTMLGenerationPurposeNormal;
    return result;
}

- (BOOL)isForPublishingProOnly
{
	return [self isForPublishing] && (nil != gRegistrationString) && gIsPro;
}

// Similar to above, but might be overridden by subclass to prevent sending to HTML validator
- (BOOL)shouldWriteServerSideScripts; { return [self isForPublishing]; }

#pragma mark CSS

@synthesize includeStyling = _includeStyling;

@synthesize mainCSS = _mainCSS;
@synthesize mainCSSURL = _mainCSSURL;

- (void)addCSSString:(NSString *)css;
{
    if (![self isForPublishing])
    {
        [self startStyleElementWithType:@"text/css"];
        [self writeText:css];
        [self endElement];
    }
}

- (void)addCSSWithURL:(NSURL *)cssURL;
{
#warning Mike, can you check if this maybe should actually be [self isForEditing] ? How does QuickLook fit in here?
    if (![self isForPublishing])
    {
        [self writeLinkToStylesheet:[self relativeURLStringOfURL:cssURL]
                              title:nil
                              media:nil];
    }
}

#pragma mark Header Tags

@synthesize currentHeaderLevel = _headerLevel;

- (NSString *)currentHeaderLevelTagName;
{
    NSString *result = [NSString stringWithFormat:@"h%u", [self currentHeaderLevel]];
    return result;
}

#pragma mark Elements/Comments

- (void)writeEndTagWithComment:(NSString *)comment;
{
    [self endElement];
    
    [self writeString:@" "];
    
    [self openComment];
    [self writeString:@" "];
    [self writeText:comment];
    [self writeString:@" "];
    [self closeComment];
}

#pragma mark Graphics

- (void)writeGraphicIgnoringCallout:(SVGraphic *)graphic
{
    // Update number of graphics
      _numberOfGraphics++;
    
    
    if ([graphic isPagelet])
    {
        // Pagelet
        SVTemplate *template = [[graphic class] template];
        
        SVHTMLTemplateParser *parser =
        [[SVHTMLTemplateParser alloc] initWithTemplate:[template templateString]
                                             component:graphic];
        
        [parser parseIntoHTMLContext:self];
        [parser release];
    }
    else if ([graphic mustBePagelet])
    {
        // Single <DIV> to enclose the graphic HTML
        //NSString *classname = [NSString stringWithFormat:@"%@", [graphic className]];
        [self startElement:@"div" className:[graphic className]];
        
        [graphic writeBody:self];
        
        // Caption if requested
        if ([graphic showsCaption])
        {
            SVHTMLTextBlock *textBlock = [[SVHTMLTextBlock alloc] init];
            [textBlock setHTMLSourceObject:graphic];
            [textBlock setHTMLSourceKeyPath:@"caption"];
            [textBlock setEditable:YES];
            [textBlock setImportsGraphics:YES];
            [textBlock setCustomCSSClassName:@"caption"];
            
            [textBlock writeHTML:self];
            [textBlock release];
        }
        
        // Finish up
        [self endElement];
    }
    else
    {
        [graphic writeBody:self];
    }
}

- (void)writeGraphic:(SVGraphic *)graphic;  // takes care of callout stuff for you
{
    // If the placement changes, want whole Text Area to update
    [self addDependencyForKeyPath:@"textAttachment.placement" ofObject:graphic];
    [self addDependencyForKeyPath:@"showsTitle" ofObject:graphic];
    [self addDependencyForKeyPath:@"showsCaption" ofObject:graphic];
    [self addDependencyForKeyPath:@"showsIntroduction" ofObject:graphic];
    
    
    // Possible callout.
    BOOL callout;
    if (callout = [graphic isCallout]) [self startCalloutForGraphic:graphic];
    
    
    [self writeGraphicIgnoringCallout: graphic];

    
    
    // Finish up
    if (callout) [self endCallout];
}

- (void)writeGraphics:(NSArray *)graphics;  // convenience
{
    for (SVGraphic *anObject in graphics)
    {
        [self writeGraphic:anObject];
    }
}

- (NSUInteger)numberOfGraphicsOnPage; { return _numberOfGraphics; }

- (void)startCalloutForGraphic:(SVGraphic *)graphic;
{
    NSString *alignment = @"";  // placeholder until we support callouts on both sides
    
    
    BOOL isSameCallout = [self isWritingCallout];
    if (isSameCallout)
    {
        // Suitable div is already open, so cancel the buffer…
        [_calloutBuffer discardBuffer];
        
        // …open elements as usual, but throw away too
        [_calloutBuffer beginBuffering];
    }
    else
    {
        OBASSERT(!_calloutAlignment);
        _calloutAlignment = [alignment copy];
    }
    
    
    // Write the opening tags
    [self startElement:@"div"
                idName:[[self currentDOMController] elementIdName]
             className:[@"callout-container " stringByAppendingString:alignment]];
    
    [self startElement:@"div" idName:nil className:@"callout"];
    
    [self startElement:@"div" idName:nil className:@"callout-content"];
    
    
    // throw away buffered writing from before
    if (isSameCallout)
    {
        [self flush];
        [_calloutBuffer discardBuffer];
    }
}

- (void)endCallout;
{
    // Buffer this call so consecutive matching callouts can be blended into one
    [_calloutBuffer beginBuffering];
    
    [self endElement]; // callout-content
    [self endElement]; // callout
    [self endElement]; // callout-container
    
    [_calloutBuffer flushOnNextWrite];
}

- (BOOL)isWritingCallout;
{
    return (_calloutAlignment != nil);
}

@synthesize calloutBuffer = _calloutBuffer;

- (void)megaBufferedWriterWillFlush:(KSMegaBufferedWriter *)buffer;
{
    OBASSERT(buffer == _calloutBuffer);
    [_calloutAlignment release]; _calloutAlignment = nil;
}

#pragma mark URLs/Paths

- (NSString *)relativeURLStringOfURL:(NSURL *)URL;
{
    OBPRECONDITION(URL);
    
    NSString *result;
    
    switch ([self generationPurpose])
    {
        case kSVHTMLGenerationPurposeEditing:
            result = [URL absoluteString];
            break;
        default:
            result = [URL stringRelativeToURL:[self baseURL]];
            break;
    }
    
    return result;
}

- (NSString *)relativeURLStringOfSiteItem:(SVSiteItem *)page;
{
    OBPRECONDITION(page);
    
    NSString *result = nil;
    
    switch ([self generationPurpose])
    {
        case kSVHTMLGenerationPurposeEditing:
            result = [page previewPath];
            break;
        case kSVHTMLGenerationPurposeQuickLookPreview:
            result= @"javascript:void(0)";
            break;
        default:
        {
            NSURL *URL = [page URL];
            if (URL) result = [self relativeURLStringOfURL:URL];
            break;
        }
    }
    
    return result;
}

- (NSString *)relativeURLStringOfPage:(id <SVPage>)page;
{
    return [self relativeURLStringOfSiteItem:(SVSiteItem *)page];
}

- (NSString *)relativeURLStringOfResourceFile:(NSURL *)resourceURL;
{
    NSString *result;
	switch ([self generationPurpose])
	{
		case kSVHTMLGenerationPurposeEditing:
			result = [resourceURL absoluteString];
			break;
            
		case kSVHTMLGenerationPurposeQuickLookPreview:
			result = [[BDAlias aliasWithPath:[resourceURL path]] quickLookPseudoTag];
			break;
			
		default:
		{
			KTHostProperties *hostProperties = [[[self page] site] hostProperties];
			NSURL *resourceFileURL = [hostProperties URLForResourceFile:[resourceURL lastPathComponent]];
			result = [resourceFileURL stringRelativeToURL:[self baseURL]];
			break;
		}
	}
    
	// TODO: Tell the delegate
	//[self didEncounterResourceFile:resourceURL];
    
	return result;
}

#pragma mark Media

- (NSURL *)addMedia:(id <SVMedia>)media;
{
    return [self addMedia:media width:nil height:nil type:nil];
}

- (NSURL *)addMedia:(id <SVMedia>)media
              width:(NSNumber *)width
             height:(NSNumber *)height
           type:(NSString *)type;
{
    OBPRECONDITION(media);
    
    NSURL *result = [media fileURL];
    if (!result) result = [[(SVMediaRecord *)media URLResponse] URL];
    
    return result;
}

- (void)writeImageWithIdName:(NSString *)idName
                   className:(NSString *)className
                 sourceMedia:(SVMediaRecord *)media
                         alt:(NSString *)altText
                       width:(NSNumber *)width
                      height:(NSNumber *)height
                        type:(NSString *)type;
{
    NSURL *URL = [self addMedia:media width:width height:height type:type];
    NSString *src = (URL ? [self relativeURLStringOfURL:URL] : @"");
    
    [self writeImageWithIdName:idName
                     className:className
                           src:src
                           alt:altText
                         width:[width description]
                        height:[height description]];
}

#pragma mark Resource Files

- (NSURL *)addResourceWithURL:(NSURL *)resourceURL;
{
    return resourceURL; // subclasses will correct for publishing
}

#pragma mark Iterations

- (NSUInteger)currentIteration; { return [[self currentIterator] iteration]; }

- (NSUInteger)currentIterationsCount; { return [[self currentIterator] count]; }

- (void)nextIteration;  // increments -currentIteration. Pops the iterators stack if this was the last one.
{
    if ([[self currentIterator] nextIteration] == NSNotFound)
    {
        [self popIterator];
    }
}

- (SVHTMLIterator *)currentIterator { return [_iteratorsStack lastObject]; }

- (void)beginIteratingWithCount:(NSUInteger)count;  // Pushes a new iterator on the stack
{
    OBPRECONDITION(count > 0);
    
    SVHTMLIterator *iterator = [[SVHTMLIterator alloc] initWithCount:count];
    [_iteratorsStack addObject:iterator];
    [iterator release];
}

- (void)popIterator;  // Pops the iterators stack early
{
    [_iteratorsStack removeLastObject];
}

#pragma mark Extra markup

- (NSMutableString *)extraHeaderMarkup; // can append to, query, as you like while parsing
{
    return _headerMarkup;
}

- (void)writeExtraHeaders;  // writes any code plug-ins etc. have requested should inside the <head> element
{
    // Start buffering into a temporary string writer
    [_postHeaderBuffer beginBuffering];
}

- (NSMutableString *)endBodyMarkup; // can append to, query, as you like while parsing
{
    return _endBodyMarkup;
}

- (void)writeEndBodyString; // writes any code plug-ins etc. have requested should go at the end of the page, before </body>
{
    // Finish buffering extra header
    [[[_postHeaderBuffer valueForKey:@"_outputs"] objectAtIndex:0]  // hack to get underlying stream
     writeString:[self extraHeaderMarkup]];
    
    [_postHeaderBuffer flush];
    
    
    // Write the end body markup
    [self writeString:[self endBodyMarkup]];
}

#pragma mark Content

// Two methods do the same thing. Need to ditch -addDependencyOnObject:keyPath: at some point
- (void)addDependencyOnObject:(NSObject *)object keyPath:(NSString *)keyPath { }
- (void)addDependencyForKeyPath:(NSString *)keyPath ofObject:(NSObject *)object;
{
    [self addDependencyOnObject:object keyPath:keyPath];
}

- (void)writeTitleOfPage:(id <SVPage>)page enclosingElement:(NSString *)element attributes:(NSDictionary *)attributes;
{
    [self startElement:element attributes:attributes];
    [self writeText:[page title]];
    [self endElement];
}

#pragma mark Raw Writing

- (void)writeAttributedHTMLString:(NSAttributedString *)attributedHTML;
{
    //  Pretty similar to -[SVRichText richText]. Perhaps we can merge the two eventually?
    
    
    NSRange range = NSMakeRange(0, [attributedHTML length]);
    NSUInteger location = 0;
    
    while (location < range.length)
    {
        NSRange effectiveRange;
        SVGraphic *attachment = [attributedHTML attribute:@"SVAttachment"
                                                  atIndex:location
                                    longestEffectiveRange:&effectiveRange
                                                  inRange:range];
        
        if (attachment)
        {
            // Write the graphic
            [self writeGraphic:attachment];
        }
        else
        {
            NSString *html = [[attributedHTML string] substringWithRange:effectiveRange];
            [self writeHTMLString:html];
        }
        
        // Advance the search
        location = location + effectiveRange.length;
    }
}

- (void)close;
{
    [super close];
    
    [_postHeaderBuffer release]; _postHeaderBuffer = nil;
    [_calloutBuffer release]; _calloutBuffer = nil;
    [_output release]; _output = nil;
}

#pragma mark Legacy

@synthesize page = _currentPage;

#pragma mark SVPlugInContext

- (id <SVHTMLWriter>)HTMLWriter; { return self; }

@end


#pragma mark -



@implementation SVHTMLIterator

- (id)initWithCount:(NSUInteger)count;
{
    [self init];
    _count = count;
    return self;
}

@synthesize count = _count;

@synthesize iteration = _iteration;

- (NSUInteger)nextIteration;
{
    _iteration = [self iteration] + 1;
    if (_iteration == [self count]) _iteration = NSNotFound;
    return _iteration;
}

@end

