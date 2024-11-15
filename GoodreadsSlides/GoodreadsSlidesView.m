//
//  GoodreadsSlidesView.m
//  GoodreadsSlides
//
//  Created by Balázs Suhajda on 2024-11-14.
//

#import "GoodreadsSlidesView.h"
#import <WebKit/WebKit.h>

@interface GoodreadsSlidesView () <NSXMLParserDelegate>
@property (strong) NSMutableArray *books;
@property (strong) NSTimer *displayTimer;
@property (strong) NSString *feedUrl;
@property (strong) NSMutableDictionary *currentBook;
@property (strong) NSMutableString *currentElementValue;
@property (strong) NSString *currentElementName;
@property (assign) NSUInteger currentBookIndex;
@property (assign) BOOL shouldUpdateImage; // Add this line
@end

@implementation GoodreadsSlidesView

- (instancetype)initWithFrame:(NSRect)frame isPreview:(BOOL)isPreview
{
    self = [super initWithFrame:frame isPreview:isPreview];
    if (self) {
        _books = [NSMutableArray array];
        _feedUrl = @"https://www.goodreads.com/review/list_rss/18906657?shelf=read";
        _currentBookIndex = 0;
        self.animationTimeInterval = 10;
        [self fetchRSSFeed];
    }
    return self;
}

- (void)startAnimation
{
    [super startAnimation];
    [self setupTimer];
}

- (void)stopAnimation
{
    [super stopAnimation];
    [self.displayTimer invalidate];
    self.displayTimer = nil;
}

- (void)drawRect:(NSRect)rect
{
    [super drawRect:rect];
    
    // Set the background color
    [[NSColor blackColor] setFill];
    NSRectFill(rect); // Fill the entire view with the background color
    
    if (self.books.count > 0) {
        NSDictionary *currentBook = self.books[self.currentBookIndex % self.books.count];
        NSImage *image = [[NSImage alloc] initWithContentsOfURL:[NSURL URLWithString:currentBook[@"book_large_image_url"]]];
        
        // Calculate the image size and position
        NSSize imageSize = image.size;
        CGFloat aspectRatio = imageSize.width / imageSize.height;
        CGFloat imageHeight = rect.size.height * 0.5; // 50% of the view height
        CGFloat imageWidth = imageHeight * aspectRatio;
        NSRect imageRect = NSMakeRect((rect.size.width - imageWidth) / 2, (rect.size.height - imageHeight) / 2, imageWidth, imageHeight);
        
        if (image) {
            [image drawInRect:imageRect];
        } else {
            [[NSColor grayColor] setFill];
            NSRectFill(imageRect); // Placeholder
        }
        
        // Prepare the attributes for drawing text
        NSMutableDictionary *attributes = [NSMutableDictionary dictionary];
        [attributes setObject:[NSFont systemFontOfSize:24] forKey:NSFontAttributeName];
        [attributes setObject:[NSColor whiteColor] forKey:NSForegroundColorAttributeName];
        
        // Draw the title
        NSString *title = currentBook[@"title"];
        NSSize titleSize = [title sizeWithAttributes:attributes];
        NSPoint titlePoint = NSMakePoint((rect.size.width - titleSize.width) / 2, imageRect.origin.y - titleSize.height - 10);
        [title drawAtPoint:titlePoint withAttributes:attributes];
        
        // Draw the author
        NSString *author = currentBook[@"author_name"];
        NSSize authorSize = [author sizeWithAttributes:attributes];
        NSPoint authorPoint = NSMakePoint((rect.size.width - authorSize.width) / 2, titlePoint.y - authorSize.height - 5);
        [author drawAtPoint:authorPoint withAttributes:attributes];
    }
    [self setNeedsDisplay:NO];
}

- (void)animateOneFrame
{
    if (self.books.count > 0) {
        self.currentBookIndex = (self.currentBookIndex + 1) % self.books.count;
        [self setNeedsDisplay:YES];
    }
}

- (void)setupTimer
{
    [self.displayTimer invalidate];
    self.displayTimer = [NSTimer scheduledTimerWithTimeInterval:1000.0
                                                             repeats:YES
                                                               block:^(NSTimer * _Nonnull timer) {
//            [self animateOneFrame];  // Trigger an update
        }];}

- (void)fetchRSSFeed
{
    [self.books removeAllObjects]; // Clear old data
        dispatch_async(dispatch_get_main_queue(), ^{
            self.currentBookIndex = 0; // Reset index
            [self setNeedsDisplay:YES]; // Force re-rendering
        });
    
    NSURL *url = [NSURL URLWithString:self.feedUrl];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    [request setValue:@"no-cache" forHTTPHeaderField:@"Cache-Control"]; // Avoid cached responses
    NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithURL:url completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (data) {
            NSXMLParser *parser = [[NSXMLParser alloc] initWithData:data];
            parser.delegate = self;
            [parser parse];
        }
        if (error) {
            NSLog(@"Error fetching RSS feed: %@", error.localizedDescription);
        }
    }];
    [task resume];
}

#pragma mark - NSXMLParserDelegate

- (void)parser:(NSXMLParser *)parser didStartElement:(NSString *)elementName namespaceURI:(NSString *)namespaceURI qualifiedName:(NSString *)qName attributes:(NSDictionary<NSString *,NSString *> *)attributeDict
{
    if ([elementName isEqualToString:@"item"]) {
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

- (void)parser:(NSXMLParser *)parser didEndElement:(NSString *)elementName namespaceURI:(NSString *)namespaceURI qualifiedName:(NSString *)qName
{
    if ([elementName isEqualToString:@"item"]) {
        [self.books addObject:self.currentBook];
    } else if ([elementName isEqualToString:@"title"] || [elementName isEqualToString:@"book_large_image_url"]) {
        [self.currentBook setObject:self.currentElementValue forKey:elementName];
    }
    self.currentElementValue = nil;
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
