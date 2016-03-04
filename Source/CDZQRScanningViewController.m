//
//  CDZQRScanningViewController.m
//
//  Created by Chris Dzombak on 10/27/13.
//  Copyright (c) 2013 Chris Dzombak. All rights reserved.
//

#import <AVFoundation/AVFoundation.h>
#import <dispatch/dispatch.h>

#import "CDZQRScanningViewController.h"
#import "CDZDiscoveredBarCodeView.h"

#ifndef CDZWeakSelf
#define CDZWeakSelf __weak __typeof__((__typeof__(self))self)
#endif

#ifndef CDZStrongSelf
#define CDZStrongSelf __typeof__(self)
#endif

static AVCaptureVideoOrientation CDZVideoOrientationFromInterfaceOrientation(UIInterfaceOrientation interfaceOrientation)
{
    switch (interfaceOrientation) {
        case UIInterfaceOrientationPortrait:
            return AVCaptureVideoOrientationPortrait;
            break;
        case UIInterfaceOrientationLandscapeLeft:
            return AVCaptureVideoOrientationLandscapeLeft;
            break;
        case UIInterfaceOrientationLandscapeRight:
            return AVCaptureVideoOrientationLandscapeRight;
            break;
        case UIInterfaceOrientationPortraitUpsideDown:
            return AVCaptureVideoOrientationPortraitUpsideDown;
            break;
        default:
            return AVCaptureVideoOrientationPortrait;
            break;
    }
}

static const float CDZQRScanningTorchLevel = 0.25;
static const NSTimeInterval CDZQRScanningTorchActivationDelay = 0.25;

NSString * const CDZQRScanningErrorDomain = @"com.cdzombak.qrscanningviewcontroller";

@interface CDZQRScanningViewController () <AVCaptureMetadataOutputObjectsDelegate>

@property (nonatomic, strong) AVCaptureSession *avSession;
@property (nonatomic, strong) AVCaptureDevice *captureDevice;
@property (nonatomic, strong) AVCaptureVideoPreviewLayer *previewLayer;

@property (nonatomic, weak) CDZDiscoveredBarCodeView *discoveredBorder;
@property (nonatomic, strong) NSTimer *timer;

@property (nonatomic, copy) NSString *lastCapturedString;

@property (nonatomic, strong, readwrite) NSArray *metadataObjectTypes;

@end

@implementation CDZQRScanningViewController

- (instancetype)initWithMetadataObjectTypes:(NSArray *)metadataObjectTypes {
    self = [super init];
    if (!self) return nil;
    self.metadataObjectTypes = metadataObjectTypes;
    self.title = NSLocalizedString(@"Scan QR Code", nil);
    return self;
}

- (instancetype)init {
    return [self initWithMetadataObjectTypes:@[ AVMetadataObjectTypeQRCode ]];
}

- (instancetype)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil {
    self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil];
    if(!self) {
        return nil;
    }
    
    self.metadataObjectTypes = @[ AVMetadataObjectTypeQRCode ];
    self.title = NSLocalizedString(@"Scan QR Code", nil);
    
    return self;
}

- (void)awakeFromNib {
    [super awakeFromNib];
    
    if(!self.metadataObjectTypes) {
        self.metadataObjectTypes = @[ AVMetadataObjectTypeQRCode ];
        self.title = NSLocalizedString(@"Scan QR Code", nil);
    }
}

- (void)viewDidLoad {
    [super viewDidLoad];

    self.view.backgroundColor = [UIColor blackColor];

    UILongPressGestureRecognizer *torchGestureRecognizer = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(handleTorchRecognizerTap:)];
    torchGestureRecognizer.minimumPressDuration = CDZQRScanningTorchActivationDelay;
    [self.view addGestureRecognizer:torchGestureRecognizer];
    
    CDZDiscoveredBarCodeView *discoveredBorder = [[CDZDiscoveredBarCodeView alloc] initWithFrame:self.view.frame];
    discoveredBorder.hidden = YES;
    discoveredBorder.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:discoveredBorder];
    self.discoveredBorder = discoveredBorder;
    
    [self.view addConstraint:[NSLayoutConstraint constraintWithItem:self.discoveredBorder attribute:NSLayoutAttributeTop relatedBy:NSLayoutRelationEqual toItem:self.view attribute:NSLayoutAttributeTop multiplier:1.0 constant:0]];
    [self.view addConstraint:[NSLayoutConstraint constraintWithItem:self.discoveredBorder attribute:NSLayoutAttributeBottom relatedBy:NSLayoutRelationEqual toItem:self.view attribute:NSLayoutAttributeBottom multiplier:1.0 constant:0]];
    [self.view addConstraint:[NSLayoutConstraint constraintWithItem:self.discoveredBorder attribute:NSLayoutAttributeLeft relatedBy:NSLayoutRelationEqual toItem:self.view attribute:NSLayoutAttributeLeft multiplier:1.0 constant:0]];
    [self.view addConstraint:[NSLayoutConstraint constraintWithItem:self.discoveredBorder attribute:NSLayoutAttributeRight relatedBy:NSLayoutRelationEqual toItem:self.view attribute:NSLayoutAttributeRight multiplier:1.0 constant:0]];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];

    if (self.cancelBlock) {
        self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCancel target:self action:@selector(cancelItemSelected:)];
    } else {
        self.navigationItem.leftBarButtonItem = nil;
    }

    self.lastCapturedString = nil;

    if (self.cancelBlock && !self.errorBlock) {
        CDZWeakSelf wSelf = self;
        self.errorBlock = ^(NSError *error) {
            CDZStrongSelf sSelf = wSelf;
            if (sSelf.cancelBlock) {
                sSelf.cancelBlock();
            }
        };
    }

    self.avSession = [[AVCaptureSession alloc] init];

    self.captureDevice = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
    if ([self.captureDevice isLowLightBoostSupported] && [self.captureDevice lockForConfiguration:nil]) {
        self.captureDevice.automaticallyEnablesLowLightBoostWhenAvailable = YES;
        [self.captureDevice unlockForConfiguration];
    }
    
    [self.avSession beginConfiguration];
    
    NSError *error = nil;
    AVCaptureDeviceInput *input = [AVCaptureDeviceInput deviceInputWithDevice:self.captureDevice error:&error];
    if (input) {
        [self.avSession addInput:input];
    } else {
        NSLog(@"QRScanningViewController: Error getting input device: %@", error);
        [self.avSession commitConfiguration];
        if (self.errorBlock) {
            dispatch_async(dispatch_get_main_queue(), ^{
                self.errorBlock(error);
            });
        }
        return;
    }
    
    AVCaptureMetadataOutput *output = [[AVCaptureMetadataOutput alloc] init];
    [self.avSession addOutput:output];
    for (NSString *type in self.metadataObjectTypes) {
        if (![output.availableMetadataObjectTypes containsObject:type]) {
            if (self.errorBlock) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    self.errorBlock([NSError errorWithDomain:CDZQRScanningErrorDomain code:CDZQRScanningViewControllerErrorUnavailableMetadataObjectType userInfo:@{NSLocalizedDescriptionKey:[NSString stringWithFormat:@"Unable to scan object of type %@", type]}]);
                });
            }
            return;
        }
    }
    
    output.metadataObjectTypes = self.metadataObjectTypes;
    [output setMetadataObjectsDelegate:self queue:dispatch_get_main_queue()];
    
    [self.avSession commitConfiguration];
    
    if (self.previewLayer.connection.isVideoOrientationSupported) {
        self.previewLayer.connection.videoOrientation = CDZVideoOrientationFromInterfaceOrientation(self.interfaceOrientation);
    }
    
    [self.avSession startRunning];

    self.previewLayer = [AVCaptureVideoPreviewLayer layerWithSession:self.avSession];
    self.previewLayer.videoGravity = AVLayerVideoGravityResizeAspectFill;
    self.previewLayer.frame = self.view.bounds;
    if (self.previewLayer.connection.isVideoOrientationSupported) {
        self.previewLayer.connection.videoOrientation = CDZVideoOrientationFromInterfaceOrientation(self.interfaceOrientation);
    }
    [self.view.layer addSublayer:self.previewLayer];
    [self.view bringSubviewToFront:self.discoveredBorder];
}

- (void)viewDidDisappear:(BOOL)animated {
    [super viewDidDisappear:animated];

    [self.previewLayer removeFromSuperlayer];
    self.previewLayer = nil;
    [self.avSession stopRunning];
    self.avSession = nil;
    self.captureDevice = nil;
    [self.timer invalidate];
    self.timer = nil;
}

- (void)willRotateToInterfaceOrientation:(UIInterfaceOrientation)toInterfaceOrientation duration:(NSTimeInterval)duration {
    [super willRotateToInterfaceOrientation:toInterfaceOrientation duration:duration];

    if (self.previewLayer.connection.isVideoOrientationSupported) {
        self.previewLayer.connection.videoOrientation = CDZVideoOrientationFromInterfaceOrientation(toInterfaceOrientation);
    }
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];

    CGRect layerRect = self.view.bounds;
    self.previewLayer.bounds = layerRect;
    self.previewLayer.position = CGPointMake(CGRectGetMidX(layerRect), CGRectGetMidY(layerRect));
}

#pragma mark - UI Actions

- (void)cancelItemSelected:(id)sender {
    !self.cancelBlock ?: self.cancelBlock();
}

- (void)handleTorchRecognizerTap:(UIGestureRecognizer *)sender {
    switch(sender.state) {
        case UIGestureRecognizerStateBegan:
            [self turnTorchOn];
            break;
        case UIGestureRecognizerStateChanged:
        case UIGestureRecognizerStatePossible:
            // no-op
            break;
        case UIGestureRecognizerStateRecognized: // also UIGestureRecognizerStateEnded
        case UIGestureRecognizerStateFailed:
        case UIGestureRecognizerStateCancelled:
            [self turnTorchOff];
            break;
    }
}

#pragma mark - Torch

- (void)turnTorchOn {
    if (self.captureDevice.hasTorch && self.captureDevice.torchAvailable && [self.captureDevice isTorchModeSupported:AVCaptureTorchModeOn] && [self.captureDevice lockForConfiguration:nil]) {
        [self.captureDevice setTorchModeOnWithLevel:CDZQRScanningTorchLevel error:nil];
        [self.captureDevice unlockForConfiguration];
    }
}

- (void)turnTorchOff {
    if (self.captureDevice.hasTorch && [self.captureDevice isTorchModeSupported:AVCaptureTorchModeOff] && [self.captureDevice lockForConfiguration:nil]) {
        self.captureDevice.torchMode = AVCaptureTorchModeOff;
        [self.captureDevice unlockForConfiguration];
    }
}

#pragma mark - Reset

- (void)reset {
  self.lastCapturedString = nil;
}

#pragma mark - AVCaptureMetadataOutputObjectsDelegate

- (NSArray<NSValue *> *)translatePoints:(NSArray *)points fromView:(UIView *)sourceView toView:(UIView *)targetView {
    NSMutableArray<NSValue *> *translatedPoints = [NSMutableArray arrayWithCapacity:points.count];
    
    for(NSDictionary *point in points) {
        CGPoint current;
        CGPointMakeWithDictionaryRepresentation((__bridge CFDictionaryRef)point, &current);
        const CGPoint converted = [sourceView convertPoint:current toView:targetView];
        
        [translatedPoints addObject:[NSValue valueWithCGPoint:converted]];
    }
    
    return translatedPoints;
}

- (void)startTimer {
    if(self.timer.isValid) {
        [self.timer invalidate];
    }
    
    self.timer = [NSTimer scheduledTimerWithTimeInterval:0.2 target:self selector:@selector(removeBorder) userInfo:nil repeats:NO];
}

- (void)removeBorder {
    self.discoveredBorder.hidden = YES;
}

- (void)captureOutput:(AVCaptureOutput *)captureOutput didOutputMetadataObjects:(NSArray *)metadataObjects fromConnection:(AVCaptureConnection *)connection {
    NSString *result;
    
    for (AVMetadataObject *metadata in metadataObjects) {
        if ([self.metadataObjectTypes containsObject:metadata.type]) {
            AVMetadataMachineReadableCodeObject *code = (AVMetadataMachineReadableCodeObject *)[self.previewLayer transformedMetadataObjectForMetadataObject:metadata];
            
            self.discoveredBorder.hidden = NO;
            [self.discoveredBorder drawBorderWithCorners:[self translatePoints:code.corners fromView:self.view toView:self.discoveredBorder]];
            
            [self startTimer];
            
            result = [code stringValue];
            break;
        }
    }

    if (result && ![self.lastCapturedString isEqualToString:result]) {
        self.lastCapturedString = result;
        
        if(self.reportingDelay > 0.0) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(self.reportingDelay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                !self.resultBlock ?: self.resultBlock(result);
            });
        } else {
            !self.resultBlock ?: self.resultBlock(result);
        }
    }
}

@end
