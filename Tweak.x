#import <UIKit/UIKit.h>
#import <WebKit/WebKit.h>
#import <objc/runtime.h>

static NSArray<NSString *> *bannedClassSubstrings;
static NSMutableSet<Class> *bannedCellClasses;
static const void *kBannedKey = &kBannedKey;

static void markBanned(UIView *c) {
    objc_setAssociatedObject(c, kBannedKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
static BOOL isBanned(UIView *c) {
    return [objc_getAssociatedObject(c, kBannedKey) boolValue];
}
static void clearBan(UIView *c) {
    objc_setAssociatedObject(c, kBannedKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static BOOL subviewHasWKWebView(UIView *v, int d) {
    if (d > 6) return NO;
    if ([v isKindOfClass:[WKWebView class]]) return YES;
    for (UIView *s in v.subviews) if (subviewHasWKWebView(s, d+1)) return YES;
    return NO;
}

static BOOL subviewHasAdLabel(UIView *v, int d) {
    if (d > 6) return NO;
    if ([v isKindOfClass:[UILabel class]]) {
        NSString *t = ((UILabel *)v).text ?: @"";
        if ([t isEqualToString:@"Promoted"] || [t isEqualToString:@"Sponsored"]) return YES;
    }
    for (UIView *s in v.subviews) if (subviewHasAdLabel(s, d+1)) return YES;
    return NO;
}

static BOOL shouldBanCell(UIView *cell) {
    if (isBanned(cell)) return YES;
    if ([bannedCellClasses containsObject:[cell class]]) return YES;
    NSString *cls = NSStringFromClass([cell class]);
    for (NSString *s in bannedClassSubstrings) {
        if ([cls rangeOfString:s options:NSCaseInsensitiveSearch].location != NSNotFound) {
            [bannedCellClasses addObject:[cell class]];
            return YES;
        }
    }
    if (subviewHasWKWebView(cell, 0)) return YES;
    if (subviewHasAdLabel(cell, 0)) return YES;
    return NO;
}

static void hideCell(UIView *cell) {
    cell.hidden = YES;
    cell.alpha = 0;
    cell.userInteractionEnabled = NO;
    // Zero the frame so layout doesn't reserve space
    cell.frame = CGRectZero;
    // Also zero via transform as belt-and-suspenders
    cell.layer.transform = CATransform3DMakeScale(1, 0.0001, 1);
    markBanned(cell);
}

%hook UICollectionViewCell

- (void)prepareForReuse {
    clearBan(self);
    self.hidden = NO;
    self.alpha = 1;
    self.userInteractionEnabled = YES;
    self.layer.transform = CATransform3DIdentity;
    %orig;
}

// setFrame: is called by the layout engine to position each cell.
// Intercept it for banned cells and force CGRectZero — this is what
// actually closes the gap because we're overriding the layout's decision.
- (void)setFrame:(CGRect)frame {
    if (isBanned(self)) {
        %orig(CGRectZero);
        return;
    }
    %orig(frame);
}

- (void)setBounds:(CGRect)bounds {
    if (isBanned(self)) {
        %orig(CGRectZero);
        return;
    }
    %orig(bounds);
}

%end

%hook UICollectionView

- (void)willDisplayCell:(UICollectionViewCell *)cell forItemAtIndexPath:(NSIndexPath *)indexPath {
    if (shouldBanCell(cell)) {
        hideCell(cell);
        NSLog(@"[NoGamePosts] banned: %@ at %@", NSStringFromClass([cell class]), indexPath);
    }
    %orig;
}

%end

%hook UITableView

- (void)willDisplayCell:(UITableViewCell *)cell forRowAtIndexPath:(NSIndexPath *)indexPath {
    if (shouldBanCell(cell)) {
        hideCell(cell);
    }
    %orig;
}

%end

%hook WKWebView

- (void)didMoveToSuperview {
    %orig;
    if (!self.superview) return;
    UIView *v = self.superview;
    UICollectionViewCell *cell = nil;
    while (v) {
        if ([v isKindOfClass:[UICollectionViewCell class]]) { cell = (UICollectionViewCell *)v; break; }
        if ([v isKindOfClass:[UIWindow class]]) break;
        v = v.superview;
    }
    if (!cell) return;
    hideCell(cell);
    NSLog(@"[NoGamePosts] WKWebView banned: %@", NSStringFromClass([cell class]));
}

%end

static void scanRuntimeClasses(void) {
    unsigned int count = 0;
    Class *classes = objc_copyClassList(&count);
    if (!classes) return;
    for (unsigned int i = 0; i < count; i++) {
        Class cls = classes[i];
        Class sup = cls;
        BOOL isCell = NO;
        while ((sup = class_getSuperclass(sup))) {
            if (sup == [UICollectionViewCell class] || sup == [UITableViewCell class]) { isCell = YES; break; }
            if (sup == [NSObject class]) break;
        }
        if (!isCell) continue;
        NSString *name = NSStringFromClass(cls);
        for (NSString *s in bannedClassSubstrings) {
            if ([name rangeOfString:s options:NSCaseInsensitiveSearch].location != NSNotFound) {
                [bannedCellClasses addObject:cls];
                break;
            }
        }
    }
    free(classes);
}

%ctor {
    @autoreleasepool {
        bannedClassSubstrings = @[
            @"Game", @"Interactive", @"Prediction", @"Trivia", @"Poll",
            @"PlayGame", @"GameWidget", @"GamePost", @"GameCard",
            @"SubGoal", @"Promo", @"Promotion", @"Promoted",
            @"JoinBanner", @"CommunityBanner", @"Announcement",
            @"SubredditPromo", @"DiscoverBanner", @"GrowthCard",
            @"Sponsored", @"Advertisement",
        ];
        bannedCellClasses = [NSMutableSet set];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)),
                       dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0), ^{
            scanRuntimeClasses();
        });
        NSLog(@"[NoGamePosts] Loaded.");
    }
}
