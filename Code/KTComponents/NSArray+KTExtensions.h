//
//  NSArray+KTExtensions.h
//  KTComponents
//
//  Copyright (c) 2005-2006, Karelia Software. All rights reserved.
//
//  THIS SOFTWARE IS PROVIDED BY KARELIA SOFTWARE AND ITS CONTRIBUTORS "AS-IS"
//  AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
//  IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
//  ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE
//  LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR 
//  CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
//  SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
//  INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
//  CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
//  ARISING IN ANY WAY OUR OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
//  POSSIBILITY OF SUCH DAMAGE.
//

#import <Cocoa/Cocoa.h>

@class KTPage;

@interface NSArray ( KTExtensions )

// standard NSArray stuff
- (id)initWithObject:(id)anObject;

- (id)objectAtReverseIndex:(int)index;

- (BOOL)containsObjectIdenticalTo:(id)object;	// Like the -indexOfObjectIdenticalTo: method

- (BOOL)containsObjectEqualToString:(NSString *)aString;

- (id)firstObject; // NSArray oddly has a lastObject method, but not a firstObject
- (id)firstObjectOrNilIfEmpty;	// Hnady to save on checking if you have nil or an empty array

- (BOOL)isEmpty;

- (void)removeObserver:(NSObject *)anObserver fromObjectsAtIndexes:(NSIndexSet *)indexes forKeyPaths:(NSSet *)keyPaths;


// operations that assume all objects in array are KTPages

/*! returns parent common to all objects in array */
- (KTPage *)commonParent;

/*! returns NO if parents differ */
- (BOOL)objectsHaveCommonParent;

/*! returns whether any object in the array is parent to aPage
	NB: this is not a sophisticated search, assumes parents
		and children are essentially in order */
- (BOOL)containsParentOfPage:(KTPage *)aPage;

/*! returns whether any object in the array isRoot */
- (BOOL)containsRoot;

/*! returns whether any object in the array isDeleted */
- (BOOL)containsDeletedObject;

/*! returns only those pages that are not children of other pages in the array */
- (NSArray *)parentObjects;

/*! Converts an NSArray with three (or four) NSValues into an RGB/RGBA Color */
-(NSColor*)		colorValue;

@end
