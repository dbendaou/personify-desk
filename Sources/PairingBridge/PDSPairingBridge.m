#import "PDSPairingBridge.h"
#import <IOBluetooth/IOBluetooth.h>

@interface PDSPairingBridge () <IOBluetoothDevicePairDelegate>
@property (nonatomic, copy) NSString *address;
@property (nonatomic, copy) NSString *pin;
@property (nonatomic, strong, nullable) IOBluetoothDevicePair *pair;
@end

@implementation PDSPairingBridge

- (instancetype)initWithAddress:(NSString *)address pin:(NSString *)pin {
    self = [super init];
    if (self) {
        _address = [address copy];
        _pin = [pin copy];
    }
    return self;
}

- (void)updatePIN:(NSString *)pin {
    @synchronized (self) {
        self.pin = [pin copy];
    }
}

- (NSString *)currentPIN {
    @synchronized (self) {
        return self.pin ?: @"";
    }
}

- (BOOL)startAndReturnError:(NSError * _Nullable * _Nullable)error {
    IOBluetoothDevice *device = [IOBluetoothDevice deviceWithAddressString:self.address];
    if (device == nil) {
        if (error) {
            *error = [NSError errorWithDomain:@"PersonifyDesk" code:1 userInfo:@{
                NSLocalizedDescriptionKey: @"IOBluetooth has no device object for that address."
            }];
        }
        return NO;
    }
    IOBluetoothDevicePair *pair = [IOBluetoothDevicePair pairWithDevice:device];
    if (pair == nil) {
        if (error) {
            *error = [NSError errorWithDomain:@"PersonifyDesk" code:2 userInfo:@{
                NSLocalizedDescriptionKey: @"IOBluetooth could not start a pairing attempt."
            }];
        }
        return NO;
    }
    self.pair = pair;
    pair.delegate = self;
    IOReturn result = [pair start];
    if (result != kIOReturnSuccess) {
        if (error) {
            *error = [NSError errorWithDomain:@"PersonifyDesk" code:result userInfo:@{
                NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Pairing start returned 0x%08x.", result]
            }];
        }
        return NO;
    }
    [self emit:@"Asked the macOS pairing API to use the code you entered."];
    return YES;
}

- (void)replyToConfirmation:(BOOL)accept {
    [self.pair replyUserConfirmation:accept];
    [self emit:accept ? @"Confirmed the numeric comparison." : @"Rejected the numeric comparison."];
}

- (void)stop {
    self.pair.delegate = nil;
    [self.pair stop];
    self.pair = nil;
}

- (void)devicePairingStarted:(IOBluetoothDevicePair *)sender {
    [self emit:@"Pairing started."];
}

- (void)devicePairingConnecting:(IOBluetoothDevicePair *)sender {
    [self emit:@"Pairing is connecting."];
}

- (void)devicePairingPINCodeRequest:(IOBluetoothDevicePair *)sender {
    NSString *pin = [self currentPIN];
    if (pin.length == 0) {
        [self emit:@"The device asked for a pairing code and none is saved."];
        void (^callback)(void) = self.onPINRequired;
        if (callback) {
            dispatch_async(dispatch_get_main_queue(), ^{
                callback();
            });
        }
        return;
    }
    NSData *bytes = [pin dataUsingEncoding:NSUTF8StringEncoding] ?: [NSData data];
    BluetoothPINCode code;
    memset(&code, 0, sizeof(code));
    NSUInteger count = MIN(bytes.length, sizeof(code.data));
    [bytes getBytes:code.data length:count];
    [self.pair replyPINCode:(ByteCount)count PINCode:&code];
    [self emit:[NSString stringWithFormat:@"The Bluetooth stack asked for a pairing code. Replied with the %lu saved digit(s).", (unsigned long)count]];
}

- (void)devicePairingUserConfirmationRequest:(IOBluetoothDevicePair *)sender numericValue:(BluetoothNumericValue)numericValue {
    [self emit:@"macOS asked to confirm a numeric comparison."];
    void (^callback)(uint32_t) = self.onNumericComparison;
    if (callback) {
        dispatch_async(dispatch_get_main_queue(), ^{
            callback((uint32_t)numericValue);
        });
    }
}

- (void)devicePairingUserPasskeyNotification:(IOBluetoothDevicePair *)sender passkey:(BluetoothPasskey)passkey {
    [self emit:@"macOS produced a passkey to enter on the other device."];
    void (^callback)(uint32_t) = self.onPasskeyDisplay;
    if (callback) {
        dispatch_async(dispatch_get_main_queue(), ^{
            callback((uint32_t)passkey);
        });
    }
}

- (void)devicePairingFinished:(IOBluetoothDevicePair *)sender error:(IOReturn)error {
    if (error == kIOReturnSuccess) {
        [self emit:@"Pairing finished."];
    } else {
        [self emit:[NSString stringWithFormat:@"Pairing finished with code 0x%08x.", error]];
        [self noteFailure];
    }
}

- (void)deviceSimplePairingComplete:(IOBluetoothDevicePair *)sender status:(BluetoothHCIEventStatus)status {
    [self emit:[NSString stringWithFormat:@"Simple pairing completed with status %u.", status]];
    if (status != 0) {
        [self noteFailure];
    }
}

- (void)noteFailure {
    void (^callback)(void) = self.onPairingFailed;
    if (callback == nil) { return; }
    dispatch_async(dispatch_get_main_queue(), ^{
        callback();
    });
}

- (void)emit:(NSString *)message {
    void (^callback)(NSString *) = self.onLog;
    if (callback == nil) { return; }
    dispatch_async(dispatch_get_main_queue(), ^{
        callback(message);
    });
}

@end
