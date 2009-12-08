//
//  SVDesignChooserImageBrowserCell.h
//  Sandvox
//
//  Created by Dan Wood on 12/8/09.
//  Copyright 2009 Karelia Software. All rights reserved.
//

#import <Cocoa/Cocoa.h>

#import <Quartz/Quartz.h>
#if MAC_OS_X_VERSION_MAX_ALLOWED > MAC_OS_X_VERSION_10_5
#else
#import "DumpedImageKit.h"
#endif



@interface SVDesignChooserImageBrowserCell : IKImageBrowserCell


// ATTENTION: since this relies on a non-documented internal behavior of IKImageBrowserView and IKImageBrowserCell 
// it could break with any system release if Apple chooses to change its implementation...
	

@end
