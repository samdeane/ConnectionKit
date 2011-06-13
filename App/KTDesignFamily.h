//
//  KTDesignFamily.h
//  Sandvox
//
//  Created by Dan Wood on 11/19/09.
//  Copyright 2009-2011 Karelia Software. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import "KTDesign.h"		// for fake protocol


@class KTDesign;

@interface KTDesignFamily : NSObject  {

	NSPointerArray *_designs;
	KTDesign *_familyPrototype;
}

- (void) addDesign:(KTDesign *)aDesign;

@property (nonatomic, assign) NSPointerArray *designs;			// weak reference so we don't have retain cycles; this is retained by a design.
@property (nonatomic, retain) KTDesign *familyPrototype;	// which design acts as the prototype, for default thumbnail.

@end