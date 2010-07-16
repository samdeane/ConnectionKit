//
//  SVURLPreviewViewController.m
//  Sandvox
//
//  Created by Mike on 15/01/2010.
//  Copyright 2010 Karelia Software. All rights reserved.
//

#import "SVURLPreviewViewController.h"

#import "SVMediaProtocol.h"
#import "SVHTMLContext.h"
#import "SVSiteItem.h"
#import "SVTemplate.h"
#import "SVTemplateParser.h"
#import "SVExternalLink.h"
#import "SVWebContentAreaController.h"

#import <BWToolkitFramework/BWToolkitFramework.h>

#import "NSString+Karelia.h"


static NSString *sURLPreviewViewControllerURLObservationContext = @"URLPreviewViewControllerURLObservation";


@interface SVURLPreviewViewController ()
@end


#pragma mark -


@implementation SVURLPreviewViewController

@synthesize metaDescription = _metaDescription;

- (void)dealloc
{
    [self setSiteItem:nil];
    [super dealloc];
}

#pragma mark View

- (void)setWebView:(WebView *)webView
{
    [super setWebView:webView];
    [webView setFrameLoadDelegate:self];
}

- (void)webView:(WebView *)sender didCommitLoadForFrame:(WebFrame *)frame;
{
    SVWebContentAreaController *tabController = (id)[self parentViewController];    // yes, hack
    if ([tabController selectedViewControllerWhenReady] == self)
    {
        [tabController setSelectedViewController:self];
    }
}

- (NSString *)HTMLTemplateAndURL:(NSURL **)outURL
{
    static SVTemplate *template;
    static NSURL *URL;
    if (!template && !URL)
    {
        URL = [[NSURL alloc] initFileURLWithPath:[[NSBundle mainBundle] pathForResource:@"Download"
                                                                                 ofType:@"html"]];
        template = [[SVTemplate alloc] initWithContentsOfURL:URL];
    }
    
    if (outURL) *outURL = URL;
    return [template templateString];
}

- (void)webView:(WebView *)sender didFailProvisionalLoadWithError:(NSError *)error forFrame:(WebFrame *)frame
{
    if (frame == [sender mainFrame])
    {
        // Build HTML
        NSURL *baseURL = nil;
        NSString *template = [self HTMLTemplateAndURL:&baseURL];
        NSMutableString *markup = [[NSMutableString alloc] init];
        
        SVHTMLContext *context = [[SVHTMLContext alloc] initWithOutputWriter:markup];
        [SVTemplateParser parseTemplate:template component:self writeToStream:context];
        
        // Load
        [frame loadAlternateHTMLString:markup
                               baseURL:baseURL
                     forUnreachableURL:[self URLToLoad]];
        
        // Tidy up
        [markup release];
        [context release];
    }
}


- (void)webView:(WebView *)sender didReceiveTitle:(NSString *)title forFrame:(WebFrame *)frame
{
    if (frame == [sender mainFrame])
    {
        [self setTitle:title];
		[self webView:sender didFinishLoadForFrame:frame];		// frame not loaded yet, but we MIGHT have the meta description by now, so try it early.
    }
}

- (void)webView:(WebView *)sender didFinishLoadForFrame:(WebFrame *)frame;
{
	if (nil == self.metaDescription && frame == [sender mainFrame])	// only check if we don't have our meta description yet
	{
		DOMDocument *domDoc = [frame DOMDocument];
		DOMNodeList *metas = [domDoc getElementsByTagName:@"meta"];
		unsigned i, length = [metas length];
		for (i = 0; i < length; i++)
		{
			DOMHTMLMetaElement *node = (DOMHTMLMetaElement *)[metas item:i];
			NSString *name = [node name];
			if ([[name lowercaseString] isEqualToString:@"description"])
			{
				NSString *content = [node content];
				
				self.metaDescription = content;		// this will then get propagated to the page details controller
				break;	// no point in looping through more meta tags
			}
		}
	}
}


#pragma mark Presentation

- (void)viewDidDisappear:(BOOL)animated
{
    [super viewDidDisappear:animated];
    
    // Did we move because of an in-progress load?
    if (![[self webView] isLoading]) [self setSiteItem:nil];
    
    // clear title, meta description, since they are not applicable anymore
	self.title = nil;
	self.metaDescription = nil;
}

#pragma mark Loading

- (BOOL)viewShouldAppear:(BOOL)animated
webContentAreaController:(SVWebContentAreaController *)controller;
{
    // Start loading the page
    [self setSiteItem:[controller selectedPage]];
    
    // Don't want to appear until the page is loaded. But if we're already on screen, that's fine
    return ([controller selectedViewController] == self);
}

@synthesize siteItem = _siteItem;
- (void)setSiteItem:(SVSiteItem *)item
{
    // teardown
    [_siteItem removeObserver:self forKeyPath:@"URL"];
    [_siteItem removeObserver:self forKeyPath:@"mediaRepresentation"];
    
    item = [item retain];
    [_siteItem release]; _siteItem = item;
    
    // observe new
    if (item)
    {
        [item addObserver:self
               forKeyPath:@"URL" 
                  options:NSKeyValueObservingOptionInitial
                  context:sURLPreviewViewControllerURLObservationContext];
        [item addObserver:self
               forKeyPath:@"mediaRepresentation" 
                  options:NSKeyValueObservingOptionInitial
                  context:sURLPreviewViewControllerURLObservationContext];
    }
    else
    {
        [[self webView] close];
        [self setWebView:nil];
        [self setView:nil];
    }
}

- (NSURL *)URLToLoad;
{
    SVSiteItem *item = [self siteItem];
    id <SVMedia> media = [item mediaRepresentation];
    
    if (media)
    {
        return [[item mediaRepresentation] fileURL];
    }
    else
    {
        return [item URL];
    }
}

- (NSString *)iconURL
{
	NSString *iconPath = [[NSBundle mainBundle] pathForImageResource:@"download"];
	NSString *result = [[NSURL fileURLWithPath:iconPath] absoluteString];
	return result;
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
    if (context == sURLPreviewViewControllerURLObservationContext)
    {
		self.title = nil;
		self.metaDescription = nil;		// clear out these data ASAP so we don't show old values
		
        // Display best representation
        NSURL *URL = [self URLToLoad];
        if (URL)
        {
            [[[self webView] mainFrame] loadRequest:[NSURLRequest requestWithURL:URL]];
        }
        else
        {
            id <SVMedia> media = [object mediaRepresentation];
            NSString *filename = [media preferredFilename];
            NSString *type = [NSString UTIForFilenameExtension:[filename pathExtension]];
                
            [[[self webView] mainFrame] loadData:[media fileContents]
                                        MIMEType:[NSString MIMETypeForUTI:type]
                                textEncodingName:nil
                                         baseURL:[object URL]];
        }
    }
    else
    {
        [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
    }
}

- (IBAction)reload:(id)sender
{
    [[self webView] reload:sender];
}

@end
