#import "GoodreadsSlidesView.h"
#import <WebKit/WebKit.h>

@interface GoodreadsSlidesView () <NSXMLParserDelegate>
@property (strong) NSMutableArray *books;
@property (strong) NSString *feedUrl;
@property (strong) NSMutableDictionary *currentBook;
@property (strong) NSMutableString *currentElementValue;
@property (strong) NSString *currentElementName;
@property (assign) NSUInteger currentBookIndex;
@property (assign) CGFloat columnWidth;
@property (strong) NSString *shelfTitle; // Stores the shelf title
@property (assign) NSUInteger numberOfBooks; // Stores the number of books
@property (assign) BOOL displayShelfInfo; // Controls display of shelf info
@property (assign) BOOL inChannel; // Flags for XML parsing
@property (assign) BOOL inItem;
@property (strong) NSMutableArray *preloadedImages;
@property (strong) NSImage *wallImage;        // Off-screen image for the wall
@property (assign) CGFloat wallImageWidth;    // Width of the wall image
@property (assign) CGFloat wallAnimationOffset; // Current offset for animation
@property (assign) NSTimeInterval shelfInfoStartTime;      // Start time for shelf info display
@property (assign) NSTimeInterval shelfInfoMinimumDuration; // Minimum duration to display shelf info
@property (assign) NSUInteger currentRSSPage; // Index of currently loading rss page
@property (assign) BOOL isFetching; // Indicates if fetching is in progress
@end

@implementation GoodreadsSlidesView

- (instancetype)initWithFrame:(NSRect)frame isPreview:(BOOL)isPreview
{
    self = [super initWithFrame:frame isPreview:isPreview];
    if (self) {
        _books = [NSMutableArray array];
        _feedUrl = @"https://www.goodreads.com/review/list_rss/18906657?shelf=read&sort=date_read";
        _currentBookIndex = 0;
        _columnWidth = 150.0; // Predefined column width
        
        // Initialize shelf info display
        _displayShelfInfo = YES;
        _shelfInfoMinimumDuration = 3.0; // Display shelf info for at least 3 seconds
        _shelfInfoStartTime = 0.0;
        _inChannel = NO;
        _inItem = NO;
        
        // Initialize pagination properties
        _currentRSSPage = 1;
        _isFetching = NO;
        
        self.animationTimeInterval = 1/30.0; // 30 FPS for smooth animation
        [self fetchRSSFeed]; // Start fetching from the first page
    }
    return self;
}

- (void)startAnimation
{
    [super startAnimation];
    self.displayShelfInfo = YES;
    self.shelfInfoStartTime = [NSDate timeIntervalSinceReferenceDate];
}

- (void)stopAnimation
{
    [super stopAnimation];
}

- (void)drawRect:(NSRect)rect
{
    [super drawRect:rect];
    
    // Set the background color
    [[NSColor blackColor] setFill];
    NSRectFill(rect);
    
    if (self.displayShelfInfo) {
        NSString *infoText;
        
        if (self.numberOfBooks == 0) {
            // Show this text before RSS pages are loaded
            infoText = @"Fetching shelf details";
        } else {
            // Display shelf title and number of books in a single line at the bottom left
            NSString *shelfTitle = self.shelfTitle ?: @"";
            infoText = [NSString stringWithFormat:@"%@ | %lu books fetched", shelfTitle, (unsigned long)self.preloadedImages.count];
        }
        
        NSFont *font = [NSFont fontWithName:@"Optima" size:24];
        if (!font) {
            // Fallback to system font
            font = [NSFont systemFontOfSize:24];
        }
        
        NSMutableParagraphStyle *paragraphStyle = [[NSMutableParagraphStyle alloc] init];
        paragraphStyle.alignment = NSTextAlignmentLeft; // Align text to the left
        
        NSDictionary *attributes = @{
            NSFontAttributeName: font,
            NSForegroundColorAttributeName: [NSColor whiteColor],
            NSParagraphStyleAttributeName: paragraphStyle
        };
        
        NSAttributedString *attributedText = [[NSAttributedString alloc] initWithString:infoText attributes:attributes];
        NSSize textSize = [attributedText size];
        
        // Position the text at the bottom left with some padding
        CGFloat padding = 20.0; // Adjust padding as needed
        NSRect textRect = NSMakeRect(padding, padding, textSize.width, textSize.height);
        
        [attributedText drawInRect:textRect];
        return;
    }
    
    if (!self.wallImage) {
        return; // Wall image is not ready
    }
    
    // Draw the wall image shifted by wallAnimationOffset
    CGFloat offset = fmod(self.wallAnimationOffset, self.wallImageWidth);
    NSRect sourceRect = NSMakeRect(offset, 0, rect.size.width, rect.size.height);
    NSRect destRect = rect;
    
    // Handle wrapping of the wall image
    if (offset + rect.size.width <= self.wallImageWidth) {
        // Draw in one piece
        [self.wallImage drawInRect:destRect fromRect:sourceRect operation:NSCompositingOperationSourceOver fraction:1.0 respectFlipped:YES hints:nil];
    } else {
        // Draw in two pieces to handle the wrap-around
        CGFloat firstPartWidth = self.wallImageWidth - offset;
        NSRect firstSourceRect = NSMakeRect(offset, 0, firstPartWidth, rect.size.height);
        NSRect firstDestRect = NSMakeRect(0, 0, firstPartWidth, rect.size.height);
        [self.wallImage drawInRect:firstDestRect fromRect:firstSourceRect operation:NSCompositingOperationSourceOver fraction:1.0 respectFlipped:YES hints:nil];
        
        CGFloat secondPartWidth = rect.size.width - firstPartWidth;
        NSRect secondSourceRect = NSMakeRect(0, 0, secondPartWidth, rect.size.height);
        NSRect secondDestRect = NSMakeRect(firstPartWidth, 0, secondPartWidth, rect.size.height);
        [self.wallImage drawInRect:secondDestRect fromRect:secondSourceRect operation:NSCompositingOperationSourceOver fraction:1.0 respectFlipped:YES hints:nil];
    }
}

- (void)animateOneFrame
{
    NSTimeInterval currentTime = [NSDate timeIntervalSinceReferenceDate];
    
    if (self.displayShelfInfo) {
        if (self.wallImage && (currentTime - self.shelfInfoStartTime) >= self.shelfInfoMinimumDuration) {
            // Shelf info has been displayed for the minimum duration and images are ready
            self.displayShelfInfo = NO;
        }
    } else if (self.wallImage) {
        // Move the wall to the left for a scrolling effect
        self.wallAnimationOffset += 1.0; // Adjust speed as needed
        
        // Keep the offset within the wall image width
        if (self.wallAnimationOffset >= self.wallImageWidth) {
            self.wallAnimationOffset -= self.wallImageWidth;
        }
    }
    
    [self setNeedsDisplay:YES];
}

- (void)fetchRSSFeed
{
    if (self.isFetching) {
        return; // Avoid multiple concurrent fetches
    }
    
    self.isFetching = YES;
    
    if (self.currentRSSPage == 1) {
        [self.books removeAllObjects]; // Clear old data if starting from page 1
        self.preloadedImages = [NSMutableArray array]; // Initialize the preloaded images array
        dispatch_async(dispatch_get_main_queue(), ^{
            self.currentBookIndex = 0; // Reset index
            [self setNeedsDisplay:YES]; // Force re-rendering
        });
    }
    
    // Construct the URL with the current page parameter
    NSString *urlString = [NSString stringWithFormat:@"%@&page=%lu", self.feedUrl, (unsigned long)self.currentRSSPage];
    NSURL *url = [NSURL URLWithString:urlString];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    [request setValue:@"no-cache" forHTTPHeaderField:@"Cache-Control"]; // Avoid cached responses
    
    NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        self.isFetching = NO;
        
        if (data) {
            // Parse the RSS feed
            NSXMLParser *parser = [[NSXMLParser alloc] initWithData:data];
            parser.delegate = self;
            BOOL parseSuccess = [parser parse];
            
            if (parseSuccess) {
                NSUInteger itemsFetched = self.books.count - self.numberOfBooks;
                self.numberOfBooks = self.books.count;
                
                if (itemsFetched == 100) {
                    // There may be more pages; increment the page number and fetch again
                    self.currentRSSPage += 1;
                    [self fetchRSSFeed];
                } else {
                    // Fetched less than 100 items; this was the last page
                    // Preload images after all pages are fetched
                    [self preloadImages];
                }
            } else {
                NSLog(@"Error parsing RSS feed");
                dispatch_async(dispatch_get_main_queue(), ^{
                    self.displayShelfInfo = NO; // Hide shelf info even if there's an error
                    [self setNeedsDisplay:YES];
                });
            }
        }
        if (error) {
            NSLog(@"Error fetching RSS feed: %@", error.localizedDescription);
            dispatch_async(dispatch_get_main_queue(), ^{
                self.displayShelfInfo = NO; // Hide shelf info even if there's an error
                [self setNeedsDisplay:YES];
            });
        }
    }];
    [task resume];
}

- (void)preloadImages
{
    dispatch_group_t group = dispatch_group_create();
    
    for (NSDictionary *book in self.books) {
        NSString *imageURLString = book[@"book_large_image_url"];
        NSURL *imageURL = [NSURL URLWithString:imageURLString];
        
        if (imageURL) {
            dispatch_group_enter(group);
            NSURLSessionDataTask *imageTask = [[NSURLSession sharedSession] dataTaskWithURL:imageURL completionHandler:^(NSData *imageData, NSURLResponse *response, NSError *error) {
                if (imageData) {
                    NSImage *image = [[NSImage alloc] initWithData:imageData];
                    if (image) {
                        @synchronized (self.preloadedImages) {
                            [self.preloadedImages addObject:@{@"image": image, @"book": book}];
                        }
                        dispatch_async(dispatch_get_main_queue(), ^{
                            [self setNeedsDisplay:YES];
                        });
                    }
                } else {
                    NSLog(@"Failed to load image from URL: %@", imageURLString);
                }
                dispatch_group_leave(group);
            }];
            [imageTask resume];
        }
    }
    
    // After all images are loaded
    dispatch_group_notify(group, dispatch_get_main_queue(), ^{
        // Build the wall image
        [self buildWallImage];
        [self setNeedsDisplay:YES];
    });
}

- (void)buildWallImage
{
    if (self.preloadedImages.count == 0) {
        return;
    }
    
    // Calculate the number of columns needed to fill the screen plus extra for seamless looping
    CGFloat screenWidth = self.bounds.size.width * 2;
    CGFloat screenHeight = self.bounds.size.height;
    NSInteger columnsNeeded = ceil(screenWidth / self.columnWidth) + 2; // Extra columns for smooth looping
    
    // Calculate the width of the wall image
    self.wallImageWidth = columnsNeeded * self.columnWidth;
    
    // Create an off-screen image to draw the wall
    self.wallImage = [[NSImage alloc] initWithSize:NSMakeSize(self.wallImageWidth, screenHeight)];
    
    [self.wallImage lockFocus];
    
    CGFloat x = 0;
    NSInteger totalImages = self.preloadedImages.count;
    NSInteger imageIndex = arc4random_uniform((uint32_t)totalImages); // Start from a random book
    
    while (x < self.wallImageWidth) {
        NSMutableArray *imagesInColumn = [NSMutableArray array];
        CGFloat columnHeight = 0;
        
        // Collect images until the total height exceeds the screen height
        while (columnHeight < screenHeight + self.columnWidth * 2) {
            NSDictionary *imageInfo = self.preloadedImages[imageIndex % totalImages];
            NSImage *image = imageInfo[@"image"];
            
            if (image) {
                // Calculate the height based on aspect ratio
                NSSize imageSize = image.size;
                CGFloat aspectRatio = imageSize.height / imageSize.width;
                CGFloat imageHeight = self.columnWidth * aspectRatio;
                [imagesInColumn addObject:@{@"image": image, @"height": @(imageHeight)}];
                columnHeight += imageHeight;
            }
            imageIndex += 1;
        }
        
        // Calculate starting y position to ensure images overflow at the top
        CGFloat y = 0;
        if (columnHeight > screenHeight) {
            y = screenHeight - columnHeight;
        }
        
        // Draw the images in the column
        for (NSDictionary *imageInfo in imagesInColumn) {
            NSImage *image = imageInfo[@"image"];
            CGFloat imageHeight = [imageInfo[@"height"] floatValue];
            NSRect imageRect = NSMakeRect(x, y, self.columnWidth, imageHeight);
            [image drawInRect:imageRect];
            y += imageHeight;
        }
        
        x += self.columnWidth;
    }
    
    [self.wallImage unlockFocus];
    
    // Reset the animation offset
    self.wallAnimationOffset = 0.0;
}

#pragma mark - NSXMLParserDelegate

- (void)parserDidStartDocument:(NSXMLParser *)parser
{
    // Initialize or reset parsing-related properties
    self.inChannel = NO;
    self.inItem = NO;
    self.currentBook = nil;
    self.currentElementValue = nil;
}

- (void)parser:(NSXMLParser *)parser didStartElement:(NSString *)elementName
  namespaceURI:(NSString *)namespaceURI
 qualifiedName:(NSString *)qName
    attributes:(NSDictionary<NSString *,NSString *> *)attributeDict
{
    if ([elementName isEqualToString:@"channel"]) {
        self.inChannel = YES;
    }
    if ([elementName isEqualToString:@"item"]) {
        self.inItem = YES;
        self.currentBook = [NSMutableDictionary dictionary];
    }
    self.currentElementName = elementName;
    self.currentElementValue = [NSMutableString string];
}

- (void)parser:(NSXMLParser *)parser foundCharacters:(NSString *)string
{
    if (self.currentElementValue) {
        [self.currentElementValue appendString:string];
    }
}

- (void)parser:(NSXMLParser *)parser didEndElement:(NSString *)elementName
  namespaceURI:(NSString *)namespaceURI
 qualifiedName:(NSString *)qName
{
    if ([elementName isEqualToString:@"channel"]) {
        self.inChannel = NO;
    } else if ([elementName isEqualToString:@"item"]) {
        [self.books addObject:self.currentBook];
        self.currentBook = nil;
        self.inItem = NO;
    } else if ([elementName isEqualToString:@"title"]) {
        if (self.inChannel && !self.inItem) {
            // This is the shelf title
            self.shelfTitle = [self.currentElementValue copy];
        } else if (self.inItem) {
            [self.currentBook setObject:[self.currentElementValue copy] forKey:@"title"];
        }
    } else if ([elementName isEqualToString:@"book_large_image_url"] && self.inItem) {
        [self.currentBook setObject:[self.currentElementValue copy] forKey:elementName];
    }
    self.currentElementValue = nil;
}

- (void)parserDidEndDocument:(NSXMLParser *)parser
{
    // Parsing completed
    // No additional actions needed here
}

- (BOOL)hasConfigureSheet
{
    return NO;
}

- (NSWindow*)configureSheet
{
    return nil;
}

@end
