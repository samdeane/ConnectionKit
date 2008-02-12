//
//  KTRTFDImporter.m
//  KTComponents
//
//  Created by Terrence Talbot on 5/3/05.
//  Copyright 2005 Biophony LLC. All rights reserved.
//

#import "KTRTFDImporter.h"

#import "Debug.h"
#import "KTDesign.h"
#import "KTOffScreenWebViewController.h"
#import "KTMaster.h"
#import "Sandvox.h"

#import "DOMNode+KTExtensions.h"
#import "NSAttributedString+Karelia.h"

#import <WebKit/WebKit.h>


@interface KTRTFDImporter ( Private )
- (NSString *)processDOMDocument:(DOMDocument *)aDOMDocument basePath:(NSString *)aBasePath requestor:(id)aRequestor;
@end


@implementation KTRTFDImporter

- (NSString *)importWithAttributedString:(NSAttributedString *)anAttrString requestor:(id)anObject
{
	NSString *snippet = [anAttrString standardSnippet];
	
	DOMDocument *aDOMDocument = [KTOffScreenWebViewController DOMDocumentForHTMLString:snippet baseURL:nil];
	if ( nil == aDOMDocument )
	{
		// FIXME: this error string could be localized
		return [NSString stringWithFormat:@"Unable to convert %@ to editable HTML.", snippet];
	}
	
	NSString *result = [self processDOMDocument:aDOMDocument basePath:@"" /* What should be specified here? */ requestor:anObject];
	return result;
}

- (NSString *)importWithContentsOfFile:(NSString *)aPath documentAttributes:(NSDictionary **)dict requestor:(id)anObject
{
	NSAttributedString *attr = [NSAttributedString attributedStringWithURL:[NSURL fileURLWithPath:aPath] documentAttributes:dict];
	if ( nil == attr )
	{
		// FIXME: this error string could be localized
		return [NSString stringWithFormat:@"Unable to read document \"%@\".", [aPath lastPathComponent]];
	}

	NSString *snippet = [attr standardSnippet];
	
	DOMDocument *aDOMDocument = [KTOffScreenWebViewController DOMDocumentForHTMLString:snippet baseURL:nil];
	if ( nil == aDOMDocument )
	{
		// FIXME: this error string could be localized
		return [NSString stringWithFormat:@"Unable to convert document %@ to HTML.", [aPath lastPathComponent]];
	}

	NSString *result = [self processDOMDocument:aDOMDocument basePath: aPath requestor:anObject];
	return result;
}

- (NSString *)processDOMDocument:(DOMDocument *)aDOMDocument basePath:(NSString *)aBasePath requestor:(id)aRequestor
{
	// here, img and object tags should be processed and turned into media objects with references
	// the Cocoa interface to nodes is defined in DOMHTML.h and DOMCore.h

	OFF((@"...................starting node analysis.................."));
	OFF((@"requestor = %@", [aRequestor className]));
	
	OBASSERT(nil != aDOMDocument);
	OBASSERT([aRequestor respondsToSelector:@selector(managedObjectContext)]);
	
	// track it with a mediaRef
	id owner = nil;
	if ( [aRequestor isKindOfClass:[KTAbstractPluginDelegate class]] )
	{
		owner = [aRequestor delegateOwner];
	}
	else
	{
		owner = aRequestor;
	}
	
	
	[aDOMDocument convertImageSourcesToUseSettingsNamed:@"inTextMediumImage" forPlugin:owner];
	
	
	// walk the DOM looking for DOMHTMLAnchorElements
//	NSArray *anchorElements = [aDOMDocument anchorElements];
//	e = [anchorElements objectEnumerator];
//	while ( element = [e nextObject] )
//	{
//		// 
//		//NSLog("anchor element = %@", [element tagName]);
//	}
	
	// walk the DOM looking for DOMHTMLLinkElements
//	NSArray *linkElements = [aDOMDocument linkElements];
//	e = [linkElements objectEnumerator];
//	while ( element = [e nextObject] )
//	{
//		// 
//		//NSLog("link element = %@", [element tagName]);
//	}
		
	OFF((@".....................end node analysis....................."));
	
	

	// Now, extract the contents of the body
	NSString *innerHTML = @"";
	DOMNodeList *bodyList = [aDOMDocument getElementsByTagName:@"BODY"];
	DOMNode *body = nil;
	if (0 == [bodyList length])
	{
		NSLog(@"unable to import because DOMNode did not have a BODY tag");
	}
	else
	{
		body = [bodyList item:0];
		
		// Now, perform surgery on the document to do the following:
		// - unwanted style attributes
		// - empty spans
		// - empty paragraphs (with maybe a break in them?)
		(void) [body removeJunkRecursiveRestrictive:NO allowEmptyParagraphs:NO];

		innerHTML = [body cleanedInnerHTML];
	}
	return innerHTML;
}


@end
