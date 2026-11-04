#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Replies to an IOBluetooth pairing request with the code the user typed.
/// CoreBluetooth has no API for that reply. This object is used only when a
/// Bluetooth address for the peripheral is already known to this Mac.
@interface PDSPairingBridge : NSObject
- (instancetype)initWithAddress:(NSString *)address pin:(NSString *)pin;
- (BOOL)startAndReturnError:(NSError * _Nullable * _Nullable)error;
- (void)updatePIN:(NSString *)pin;
- (void)replyToConfirmation:(BOOL)accept NS_SWIFT_NAME(replyToConfirmation(_:));
- (void)stop;
@property (nonatomic, copy, nullable) void (^onLog)(NSString *_Nonnull message);
@property (nonatomic, copy, nullable) void (^onNumericComparison)(uint32_t value);
@property (nonatomic, copy, nullable) void (^onPasskeyDisplay)(uint32_t passkey);
/// The stack asked for a code and none was available to reply with.
@property (nonatomic, copy, nullable) void (^onPINRequired)(void);
/// Pairing finished with an error, or simple pairing reported a non-zero status.
@property (nonatomic, copy, nullable) void (^onPairingFailed)(void);
@end

NS_ASSUME_NONNULL_END
