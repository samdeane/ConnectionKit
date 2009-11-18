//
//  SVDesignChooserViewController.m
//  Sandvox
//
//  Created by Terrence Talbot on 8/28/09.
//  Copyright 2009 Karelia Software. All rights reserved.
//

#import "SVDesignChooserViewController.h"
#import "NSBundle+Karelia.h"
#import "KSPlugin.h"
#import "KT.h"

@interface NSCollectionView (SnowLeopardOnly)

- (NSRect)frameForItemAtIndex:(NSUInteger)index;

@end

@implementation SVDesignChooserViewController

- (void)awakeFromNib
{
    // load designs -- only seems to work if I do it here? seems as good a place as any...
    [self setDesigns:[KSPlugin sortedPluginsWithFileExtension:kKTDesignExtension]];
    
    // restrict to a max of 4 columns
    [oCollectionView setMaxNumberOfColumns:4];
	
	NSCollectionViewItem *prototype = [[[NSCollectionViewItem alloc] init] autorelease];
	[[NSBundle mainBundle] loadNibNamed:@"SVDesignViewPrototype" owner:prototype];
	[oCollectionView setItemPrototype:prototype];
}

- (void) setupTrackingRects;		// do this after the view is added and resized
{
	return;
	
	trackingRect_ = [oCollectionView addTrackingRect:[oCollectionView frame] owner:self userData:nil assumeInside:NO];
	
	// a register for those notifications on the synchronized content view.
    [[NSNotificationCenter defaultCenter] addObserver:self
											 selector:@selector(viewBoundsDidChange:)
												 name:NSViewBoundsDidChangeNotification
											   object:oCollectionView];
}


- (void)mouseEntered:(NSEvent *)theEvent
{
	wasAcceptingMouseEvents_ = [[oCollectionView window] acceptsMouseMovedEvents];
	[[oCollectionView window] setAcceptsMouseMovedEvents:YES];
    [[oCollectionView window] makeFirstResponder:self];

	NSLog(@"%s %@",__FUNCTION__, theEvent);
}
- (void)mouseExited:(NSEvent *)theEvent
{
    [[oCollectionView window] setAcceptsMouseMovedEvents:wasAcceptingMouseEvents_];
	NSLog(@"%s %@",__FUNCTION__, theEvent);
}
- (void)mouseMoved:(NSEvent *)theEvent
{
#define CELLWIDTH 150
#define CELLHEIGHT 112
//	NSLog(@"%s %@",__FUNCTION__, theEvent);
	NSPoint windowPoint = [theEvent locationInWindow];
	NSPoint localPoint = [oCollectionView convertPoint:windowPoint fromView:nil];

	NSSize itemSize = NSMakeSize(CELLWIDTH,CELLHEIGHT);		// this is constant in our case ... is there any good way to query this?
	int xIndex = localPoint.x / itemSize.width;
	int yIndex = localPoint.y / itemSize.height;
	int listIndex = yIndex * 4 + xIndex;
	if (listIndex <= [[oCollectionView content] count])
	{
		
		NSRect frameForItemAtIndex = NSMakeRect(CELLWIDTH*xIndex, CELLHEIGHT*yIndex, CELLWIDTH, CELLHEIGHT);
		NSRect frameForItemAtIndexManual = frameForItemAtIndex;
		
		if ([oCollectionView respondsToSelector:@selector(frameForItemAtIndex:)])		// 10.6
		{
			frameForItemAtIndex = [oCollectionView frameForItemAtIndex:listIndex];
		}
		
		NSLog(@"%@ %d,%d -> %d : %@ %@",NSStringFromPoint(localPoint), xIndex,yIndex, listIndex, NSStringFromRect(frameForItemAtIndex), NSStringFromRect(frameForItemAtIndexManual));
	}
	else
	{
		NSLog(@"out of bounds");
	}
}



- (void)viewBoundsDidChange:(NSNotification *)aNotif;
{
    // we set up a tracking region so we can get mouseEntered and mouseExited events
    [oCollectionView removeTrackingRect:trackingRect_];
    trackingRect_ = [oCollectionView addTrackingRect:[oCollectionView frame] owner:self userData:nil assumeInside:NO];
}

@synthesize designs = designs_;
@synthesize designsArrayController = oArrayController;
@synthesize designsCollectionView = oCollectionView;
@end

@implementation SVDesignChooserScrollView

- (void)awakeFromNib
{
    //NSColor *startingColor = [NSColor darkGrayColor];
    //NSColor *endingColor = [NSColor blackColor];
    //backgroundGradient_ = [[NSGradient alloc] initWithStartingColor:startingColor
    //                                                    endingColor:endingColor];    
}

- (void)drawRect:(NSRect)rect
{
    //[backgroundGradient_ drawInRect:[self bounds] angle:90.0];
    //[[NSColor colorWithCalibratedRed:0.079 green:0.079 blue:0.079 alpha:1.000] set];
    //[NSBezierPath fillRect:rect];
}

- (void)dealloc
{
    //[backgroundGradient_ release];
    [super dealloc];
}

@end

@implementation SVDesignChooserViewBox

- (NSView *)hitTest:(NSPoint)aPoint
{
    return nil; // don't allow any mouse clicks for subviews (needed?)
}

@end

@implementation SVDesignChooserSelectionView


// view's hidden binding is bound to viewcontoller.selection (NSNegateBoolean)
// so this only appears drawn around the selection
- (void)drawRect:(NSRect)rect
{
	// draw a rectangle under where the highlight will go
    NSBezierPath *underPath = [NSBezierPath bezierPathWithRect:rect];
    [underPath setLineWidth:3.0];
    [underPath setLineJoinStyle:NSRoundLineJoinStyle];
    [[NSColor colorWithCalibratedWhite:0.10 alpha:1.0] set];
    [underPath stroke];
	
    // do a thicker line in selectedControlColor to indicate selection
    NSBezierPath *highlightPath = [NSBezierPath bezierPathWithRoundedRect:NSInsetRect(rect, 1.5, 1.5) xRadius:9.0 yRadius:9.0];
    [highlightPath setLineWidth:3.0];
    [highlightPath setLineJoinStyle:NSRoundLineJoinStyle];
    [[NSColor alternateSelectedControlColor] set];
    [highlightPath stroke];
}

@end
