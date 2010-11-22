//
//  SVGraphicDOMController.h
//  Sandvox
//
//  Created by Mike on 23/02/2010.
//  Copyright 2010 Karelia Software. All rights reserved.
//

#import "SVDOMController.h"
#import "SVGraphic.h"
#import "SVOffscreenWebViewController.h"


@interface SVGraphicDOMController : SVDOMController <SVOffscreenWebViewControllerDelegate>
{
  @private
    DOMHTMLElement  *_bodyElement;
    
    SVOffscreenWebViewController    *_offscreenWebViewController;
    
    BOOL    _moving;
    CGPoint _relativePosition;
}

+ (SVGraphicDOMController *)graphicPlaceholderDOMController;

@property(nonatomic, retain) DOMHTMLElement *bodyHTMLElement;
- (DOMElement *)graphicDOMElement;
- (void)loadPlaceholderDOMElementInDocument:(DOMDocument *)document;

- (void)update;
- (void)updateSize;


#pragma mark Moving
- (void)moveToRelativePosition:(CGPoint)position;
- (void)moveToPosition:(CGPoint)position;   // takes existing relative position into account
- (void)removeRelativePosition:(BOOL)animated;
- (BOOL)hasRelativePosition;
- (CGPoint)positionIgnoringRelativePosition;


@end


#pragma mark -


@interface WEKWebEditorItem (SVGraphicDOMController)
- (SVGraphicDOMController *)enclosingGraphicDOMController;
@end


#pragma mark -


// And provide a base implementation of the protocol:
@interface SVGraphic (SVDOMController) <SVDOMControllerRepresentedObject>
- (SVDOMController *)newBodyDOMController;
@end


#pragma mark -


@interface SVGraphicBodyDOMController : SVDOMController
{
@private
    BOOL    _drawAsDropTarget;
}

@end
