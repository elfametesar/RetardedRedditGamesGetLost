// NoGamePosts - Hides Reddit Games/Interactive posts from feed
// Primary: WKWebView-in-cell detection (catches embedded game widgets)
// Fallback: class name + accessibility scan for native game cell types
// Works rootless (TrollStore/AltStore sideload)

#import <UIKit/UIKit.h>
#import <WebKit/WebKit.h>
#import <objc/runtime.h>

static NSArray<NSString *> *gameClassSubstrings;
static NSArray<NSString *> *gameAccessibilitySubstrings;
static NSMutableSet<Class> *knownGameCellClasses;

// Forward declarations
static BOOL subviewContainsGameMarker(UIView *view);
static void collapseCell(UIView *cell);
static void restoreCell(UIView *cell);

static UIView *parentFeedCell(UIView *view) {
    UIView *current = view.superview;
    while (current) {
        if ([current isKindOfClass:[UICollectionViewCell class]] ||
            [current isKindOfClass:[UITableViewCell class]]) {
            return current;
        }
        if ([current isKindOfClass:[UIWindow class]]) {
            return nil;
        }
        current = current.superview;
    }
    return nil;
}

static void collapseCell(UIView *cell) {
    cell.hidden = YES;
    cell.alpha = 0.0;
    cell.transform = CGAffineTransformMakeScale(1.0, 0.001);
    cell.userInteractionEnabled = NO;
}

static void restoreCell(UIView *cell) {
    cell.hidden = NO;
    cell.alpha = 1.0;
    cell.transform = CGAffineTransformIdentity;
    cell.userInteractionEnabled = YES;
}

static BOOL subviewContainsGameMarker(UIView *view) {
    NSString *testId = view.accessibilityIdentifier ?: @"";
    for (NSString *substr in gameAccessibilitySubstrings) {
        if ([testId rangeOfString:substr options:NSCaseInsensitiveSearch].location != NSNotFound) {
            return YES;
        }
    }
    static NSInteger depth = 0;
    if (depth >= 4) return NO;
    depth++;
    for (UIView *subview in view.subviews) {
        if (subviewContainsGameMarker(subview)) {
            depth--;
            return YES;
        }
    }
    depth--;
    return NO;
}

static BOOL isGameCellByClassName(UIView *cell) {
    if ([knownGameCellClasses containsObject:[cell class]]) return YES;
    NSString *className = NSStringFromClass([cell class]);
    for (NSString *substr in gameClassSubstrings) {
        if ([className rangeOfString:substr options:NSCaseInsensitiveSearch].location != NSNotFound) {
            [knownGameCellClasses addObject:[cell class]];
            return YES;
        }
    }
    NSString *combined = [NSString stringWithFormat:@"%@%@",
        cell.accessibilityIdentifier ?: @"",
        cell.accessibilityLabel ?: @""];
    for (NSString *substr in gameAccessibilitySubstrings) {
        if ([combined rangeOfString:substr options:NSCaseInsensitiveSearch].location != NSNotFound) {
            return YES;
        }
    }
    return subviewContainsGameMarker(cell);
}

%hook WKWebView

- (void)didMoveToSuperview {
    %orig;
    if (!self.superview) return;

    UIView *feedCell = parentFeedCell(self);
    if (!feedCell) return;

    UICollectionView *cv = nil;
    UIView *v = feedCell.superview;
    while (v) {
        if ([v isKindOfClass:[UICollectionView class]]) { cv = (UICollectionView *)v; break; }
        if ([v isKindOfClass:[UIWindow class]]) break;
        v = v.superview;
    }

    NSLog(@"[NoGamePosts] WKWebView detected in feed cell class: %@, URL: %@",
          NSStringFromClass([feedCell class]),
          self.URL ?: @"(not loaded yet)");

    collapseCell(feedCell);
    [knownGameCellClasses addObject:[feedCell class]];

    if (cv) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [cv.collectionViewLayout invalidateLayout];
        });
    }
}

- (void)didMoveToWindow {
    %orig;
    if (!self.window) return;
    UIView *feedCell = parentFeedCell(self);
    if (!feedCell) return;
    collapseCell(feedCell);
}

%end

%hook UICollectionView

- (void)willDisplayCell:(UICollectionViewCell *)cell forItemAtIndexPath:(NSIndexPath *)indexPath {
    if (isGameCellByClassName(cell)) {
        collapseCell(cell);
        NSLog(@"[NoGamePosts] Collapsed by class scan: %@ at [%ld,%ld]",
              NSStringFromClass([cell class]),
              (long)indexPath.section, (long)indexPath.item);
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.collectionViewLayout invalidateLayout];
        });
        return;
    }
    if ([knownGameCellClasses containsObject:[cell class]]) {
        collapseCell(cell);
        return;
    }
    if (cell.hidden && cell.transform.d < 0.5) {
        restoreCell(cell);
    }
    %orig;
}

- (void)didEndDisplayingCell:(UICollectionViewCell *)cell forItemAtIndexPath:(NSIndexPath *)indexPath {
    if (cell.transform.d < 0.5 && ![knownGameCellClasses containsObject:[cell class]]) {
        restoreCell(cell);
    }
    %orig;
}

%end

%hook UITableView

- (void)willDisplayCell:(UITableViewCell *)cell forRowAtIndexPath:(NSIndexPath *)indexPath {
    if (isGameCellByClassName(cell)) {
        collapseCell(cell);
        return;
    }
    if ([knownGameCellClasses containsObject:[cell class]]) {
        collapseCell(cell);
        return;
    }
    if (cell.hidden && cell.transform.d < 0.5) {
        restoreCell(cell);
    }
    %orig;
}

%end

static void scanRuntimeClasses(void) {
    unsigned int classCount = 0;
    Class *classes = objc_copyClassList(&classCount);
    if (!classes) return;
    for (unsigned int i = 0; i < classCount; i++) {
        Class cls = classes[i];
        Class sup = cls;
        BOOL isCell = NO;
        while ((sup = class_getSuperclass(sup))) {
            if (sup == [UICollectionViewCell class] || sup == [UITableViewCell class]) {
                isCell = YES; break;
            }
            if (sup == [NSObject class]) break;
        }
        if (!isCell) continue;
        NSString *name = NSStringFromClass(cls);
        for (NSString *substr in gameClassSubstrings) {
            if ([name rangeOfString:substr options:NSCaseInsensitiveSearch].location != NSNotFound) {
                [knownGameCellClasses addObject:cls];
                NSLog(@"[NoGamePosts] Pre-cached: %@", name);
                break;
            }
        }
    }
    free(classes);
}

%ctor {
    @autoreleasepool {
        gameClassSubstrings = @[
            @"Game", @"Interactive", @"Prediction", @"Trivia",
            @"Poll", @"PlayGame", @"GameWidget", @"GamePost",
            @"GameCard", @"InteractivePost", @"InteractiveCard",
        ];
        gameAccessibilitySubstrings = @[
            @"game", @"interactive_post", @"prediction",
            @"trivia", @"play-game", @"game-widget",
            @"game_post", @"reddit_game",
        ];
        knownGameCellClasses = [NSMutableSet set];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)),
                       dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0), ^{
            scanRuntimeClasses();
        });
        NSLog(@"[NoGamePosts] Loaded. WKWebView hook active.");
    }
}
