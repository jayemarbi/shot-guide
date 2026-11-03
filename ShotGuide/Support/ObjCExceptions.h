#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Runs `block` and hands back any Objective-C exception it raises, instead of letting it crash the app.
/// AVFoundation raises them for things like starting a recording before the camera is ready.
NSException * _Nullable SGCatchException(NS_NOESCAPE void (^block)(void));

NS_ASSUME_NONNULL_END
