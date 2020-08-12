#import "FFFastImageViewManager.h"
#import "FFFastImageView.h"

#import <SDWebImage/SDWebImagePrefetcher.h>
#import <SDWebImage/SDImageCache.h>

@implementation FFFastImageViewManager

RCT_EXPORT_MODULE(FastImageView)

- (FFFastImageView*)view {
  return [[FFFastImageView alloc] init];
}

RCT_EXPORT_VIEW_PROPERTY(source, FFFastImageSource)
RCT_EXPORT_VIEW_PROPERTY(resizeMode, RCTResizeMode)
RCT_EXPORT_VIEW_PROPERTY(onFastImageLoadStart, RCTDirectEventBlock)
RCT_EXPORT_VIEW_PROPERTY(onFastImageProgress, RCTDirectEventBlock)
RCT_EXPORT_VIEW_PROPERTY(onFastImageError, RCTDirectEventBlock)
RCT_EXPORT_VIEW_PROPERTY(onFastImageLoad, RCTDirectEventBlock)
RCT_EXPORT_VIEW_PROPERTY(onFastImageLoadEnd, RCTDirectEventBlock)
RCT_REMAP_VIEW_PROPERTY(tintColor, imageColor, UIColor)

RCT_EXPORT_METHOD(preload:(nonnull NSArray<FFFastImageSource *> *)sources)
{
    NSMutableArray *urls = [NSMutableArray arrayWithCapacity:sources.count];

    [sources enumerateObjectsUsingBlock:^(FFFastImageSource * _Nonnull source, NSUInteger idx, BOOL * _Nonnull stop) {
        [source.headers enumerateKeysAndObjectsUsingBlock:^(NSString *key, NSString* header, BOOL *stop) {
            [[SDWebImageDownloader sharedDownloader] setValue:header forHTTPHeaderField:key];
        }];
        [urls setObject:source.url atIndexedSubscript:idx];
    }];

    [[SDWebImagePrefetcher sharedImagePrefetcher] prefetchURLs:urls];
}

RCT_REMAP_METHOD(
  loadImage,
  loadImageWithSource: (nonnull FFFastImageSource *)source resolver:(RCTPromiseResolveBlock)resolve rejecter:(RCTPromiseRejectBlock)reject
) {
  SDWebImageManager *imageManager = [SDWebImageManager sharedManager];
  SDImageCache *cache = (SDImageCache *) imageManager.imageCache;
  
  // Set headers.
  NSDictionary *headers = source.headers;
  SDWebImageDownloaderRequestModifier *requestModifier = [SDWebImageDownloaderRequestModifier requestModifierWithBlock:^NSURLRequest * _Nullable(NSURLRequest * _Nonnull request) {
      NSMutableURLRequest *mutableRequest = [request mutableCopy];
      for (NSString *header in headers) {
          NSString *value = headers[header];
          [mutableRequest setValue:value forHTTPHeaderField:header];
      }
      return [mutableRequest copy];
  }];
  SDWebImageContext *context = @{SDWebImageContextDownloadRequestModifier : requestModifier};
  
  // Set priority.
  SDWebImageOptions options = SDWebImageRetryFailed | SDWebImageHandleCookies;
  switch (source.priority) {
      case FFFPriorityLow:
          options |= SDWebImageLowPriority;
          break;
      case FFFPriorityNormal:
          // Priority is normal by default.
          break;
      case FFFPriorityHigh:
          options |= SDWebImageHighPriority;
          break;
  }
  
  switch (source.cacheControl) {
      case FFFCacheControlWeb:
          options |= SDWebImageRefreshCached;
          break;
      case FFFCacheControlCacheOnly:
          options |= SDWebImageFromCacheOnly;
          break;
      case FFFCacheControlImmutable:
          break;
  }
  
  // load image
  [imageManager loadImageWithURL:source.url options:options context:context progress:nil completed:^(UIImage * _Nullable image, NSData * _Nullable data, NSError * _Nullable error, SDImageCacheType cacheType, BOOL finished, NSURL * _Nullable imageURL) {
    if (error != nil) {
      reject(@"FastImage", @"Failed to load image", error);
      return;
    }

    NSString *cacheKey = [imageManager cacheKeyForURL:source.url];
    // store image manually (since image manager may call the completion block before storing it in the disk cache)
    [cache storeImage:image forKey:cacheKey completion:^{
      NSString *imagePath = [cache cachePathForKey:cacheKey];
      resolve(imagePath);
    }];
  }];
}

@end

