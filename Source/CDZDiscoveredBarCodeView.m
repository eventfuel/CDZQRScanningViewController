//
//  CDZDiscoveredBarCodeView.m
//  CDZQRScanningViewController
//
//  Created by Vasco d'Orey on 03/03/16.
//  Copyright © 2016 Tasboa. All rights reserved.
//

#import "CDZDiscoveredBarCodeView.h"

@interface CDZDiscoveredBarCodeView ()

@property (nonatomic, weak) CAShapeLayer *borderLayer;

@property (nonatomic, strong) NSArray<NSValue *> *corners;

@end

@implementation CDZDiscoveredBarCodeView

#pragma mark -
#pragma mark Initialization

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (!self) {
        return nil;
    }
    
    CAShapeLayer *borderLayer = ({
        CAShapeLayer *layer = [CAShapeLayer layer];
        
        layer.strokeColor = [UIColor redColor].CGColor;
        layer.borderWidth = 2;
        layer.fillColor = [UIColor clearColor].CGColor;
        
        layer;
    });
    [self.layer addSublayer:borderLayer];
    _borderLayer = borderLayer;
    
    return self;
}

#pragma mark -
#pragma mark Public API

- (void)drawBorderWithCorners:(NSArray<NSValue *> *)corners {
    self.corners = corners;
    
    const UIBezierPath *bezierPath = ({
        UIBezierPath *path = [UIBezierPath bezierPath];
        NSValue *firstValue = corners.firstObject;
        CGPoint firstPoint = [firstValue CGPointValue];
        
        [path moveToPoint:firstPoint];
        
        [corners enumerateObjectsUsingBlock:^(NSValue * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
            if(idx > 0) {
                CGPoint point = [obj CGPointValue];
                
                [path addLineToPoint:point];
            }
        }];
        
        [path addLineToPoint:firstPoint];
        
        path;
    });
    
    self.borderLayer.path = bezierPath.CGPath;
}

@end
