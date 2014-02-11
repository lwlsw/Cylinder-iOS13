#import <substrate.h>
#import <UIKit/UIKit.h>
#import "luashit.h"
#import "macros.h"

static Class SBIconListView;
static IMP original_SB_scrollViewWillBeginDragging;
static IMP original_SB_scrollViewDidScroll;
static IMP original_SB_scrollViewDidEndDecelerating;
static IMP original_SB_wallpaperRelativeBounds;

static BOOL _enabled;

void reset_everything(UIView *view)
{
    view.layer.transform = CATransform3DIdentity;
    view.alpha = 1;
    for(UIView *v in view.subviews)
    {
        v.layer.transform = CATransform3DIdentity;
        v.alpha = 1;
    }
}

void genscrol(UIScrollView *scrollView, int i, UIView *view)
{
    CGSize size = scrollView.frame.size;
    float offset = scrollView.contentOffset.x;
    if(IOS_VERSION < 7) i++; //on iOS 6-, the spotlight is a page to the left, so we gotta bump the pageno. up a notch
    offset -= i*size.width;

    _enabled = manipulate(view, offset, size.width, size.height);
}

void SB_scrollViewDidEndDecelerating(id self, SEL _cmd, UIScrollView *scrollView)
{
    original_SB_scrollViewDidEndDecelerating(self, _cmd, scrollView);
    for(UIView *view in scrollView.subviews)
        reset_everything(view);
}

void SB_scrollViewWillBeginDragging(id self, SEL _cmd, UIScrollView *scrollView)
{
    original_SB_scrollViewWillBeginDragging(self, _cmd, scrollView);
    [scrollView.superview sendSubviewToBack:scrollView];
}

void SB_scrollViewDidScroll(id self, SEL _cmd, UIScrollView *scrollView)
{
    original_SB_scrollViewDidScroll(self, _cmd, scrollView);

    if(!_enabled) return;

    float percent = scrollView.contentOffset.x/scrollView.frame.size.width;
    if(IOS_VERSION < 7) percent--;

    for(int i = 0; i < scrollView.subviews.count; i++)
    {
        UIView *view = [scrollView.subviews objectAtIndex:i];
        if([view isKindOfClass:SBIconListView])
        {
            int index = (int)(percent + i);
            if(index >= 0 && index < scrollView.subviews.count)
            {
                view = [scrollView.subviews objectAtIndex:index];
                if([view isKindOfClass:SBIconListView])
                    genscrol(scrollView, index - i, view);
            }
            int index2 = (int)(percent + i + 1);
            if(index != index2 && index2 >= 0 && index2 < scrollView.subviews.count)
            {
                view = [scrollView.subviews objectAtIndex:index2];
                if([view isKindOfClass:SBIconListView])
                    genscrol(scrollView, index2 - i, view);
            }
            break;
        }
    }
}

//iOS 7 folder blur glitch hotfix for 3D effects.
typedef CGRect (*wprb_type)(id, SEL);
CGRect SB_wallpaperRelativeBounds(id self, SEL _cmd)
{
    wprb_type func = (wprb_type)(original_SB_wallpaperRelativeBounds);
    CGRect frame = func(self, _cmd);
    if(frame.origin.x < 0) frame.origin.x = 0;
    if(frame.origin.x > SCREEN_SIZE.width - frame.size.width) frame.origin.x = SCREEN_SIZE.width - frame.size.width;
    if(frame.origin.y > SCREEN_SIZE.height - frame.size.height) frame.origin.y = SCREEN_SIZE.height - frame.size.height;
    if(frame.origin.y < 0) frame.origin.y = 0;
    return frame;
}

void load_that_shit()
{
    NSDictionary *settings = [NSDictionary dictionaryWithContentsOfFile:PREFS_PATH];

    if(settings && ![[settings valueForKey:@"enabled"] boolValue])
    {
        close_lua();
        _enabled = false;
    }
    else
    {
        NSString *key = [settings valueForKey:PrefsEffectKey];
        _enabled = init_lua(key.UTF8String);
    }
}

static inline void setSettingsNotification(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo)
{
    load_that_shit();
}

// The attribute forces this function to be called on load.
__attribute__((constructor))
static void initialize() {
    SBIconListView = NSClassFromString(@"SBIconListView");
    load_that_shit();

    //hook scroll
    Class cls = NSClassFromString(IOS_VERSION < 7 ? @"SBIconController" : @"SBFolderView");

    MSHookMessageEx(cls, @selector(scrollViewDidScroll:), (IMP)SB_scrollViewDidScroll, (IMP *)&original_SB_scrollViewDidScroll);
    MSHookMessageEx(cls, @selector(scrollViewDidEndDecelerating:), (IMP)SB_scrollViewDidEndDecelerating, (IMP *)&original_SB_scrollViewDidEndDecelerating);
    if(IOS_VERSION < 7)
        MSHookMessageEx(cls, @selector(scrollViewWillBeginDragging:), (IMP)SB_scrollViewWillBeginDragging, (IMP *)&original_SB_scrollViewWillBeginDragging);
    cls = NSClassFromString(@"SBFolderIconBackgroundView");
    if(cls) MSHookMessageEx(cls, @selector(wallpaperRelativeBounds), (IMP)SB_wallpaperRelativeBounds, (IMP *)&original_SB_wallpaperRelativeBounds);

    //listen to notification center (for settings change)
    CFNotificationCenterRef r = CFNotificationCenterGetDarwinNotifyCenter();
    CFNotificationCenterAddObserver(r, NULL, &setSettingsNotification, (CFStringRef)kCylinderSettingsChanged, NULL, 0);
}