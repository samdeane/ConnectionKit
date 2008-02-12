//
//  NSFileManager+KTExtensions.h
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


@interface NSFileManager ( KTExtensions )

/*! creates intermediate directories using -createDirectoryAtPath:attributes
    i.e., sort of like mkdir -p
*/
- (BOOL)createDirectoryPath:(NSString *)path attributes:(NSDictionary *)attributes;

- (NSData *)readFromResourceFileAtPath:(NSString *)aPath type:(ResType)aType named:(NSString *)aName id:(short int)anID;
- (NSString *)resolvedAliasPath:(NSString *)aPath;

/*! returns NSFileSize or nil if aPath does not exist */
- (NSNumber *)sizeOfFileAtPath:(NSString *)aPath;

- (BOOL)setExtensionHiddenAtPath:(NSString *)aPath;

- (NSString *)uniqueFilenameAtPath:(NSString *)startingPath;

@end
