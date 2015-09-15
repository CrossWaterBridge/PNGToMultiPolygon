//
//  main.m
//  PNGToMultiPolygon
//
//  Created by Hilton Campbell on 8/24/15.
//  Copyright (c) 2015 LDS Mobile Apps. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import "clipper.hpp"

int main(int argc, const char * argv[]) {
    @autoreleasepool {
        if (argc != 2) {
            NSString *command = [NSString stringWithUTF8String:argv[0]];
            NSLog(@"usage: %@ <path>", [command lastPathComponent]);
            return 1;
        }
        
        NSString *path = [NSString stringWithUTF8String:argv[1]];
        
        CGDataProviderRef dataProvider = CGDataProviderCreateWithCFData((CFDataRef)[NSData dataWithContentsOfFile:path]);
        CGImageRef image = CGImageCreateWithPNGDataProvider(dataProvider, NULL, NO, kCGRenderingIntentDefault);
        
        NSUInteger width = CGImageGetWidth(image);
        NSUInteger height = CGImageGetHeight(image);
        CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
        unsigned char *rawData = (unsigned char *)malloc(height * width * 4);
        NSUInteger bytesPerPixel = 4;
        NSUInteger bytesPerRow = bytesPerPixel * width;
        NSUInteger bitsPerComponent = 8;
        CGContextRef context = CGBitmapContextCreate(rawData, width, height,
                                                     bitsPerComponent, bytesPerRow, colorSpace,
                                                     kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
        CGColorSpaceRelease(colorSpace);
        
        CGContextDrawImage(context, CGRectMake(0, 0, width, height), image);
        CGContextRelease(context);
        
        ClipperLib::Clipper clipper;
        
        int x = 0;
        int y = 0;
        for (x = 0; x < width; x++) {
            for (y = 0; y < height; y++) {
                unsigned char alphaByte = rawData[(y*bytesPerRow)+(x*bytesPerPixel)+3];
                if (alphaByte > 0) {
                    ClipperLib::Path path;
                    path << ClipperLib::IntPoint(x, y);
                    path << ClipperLib::IntPoint(x + 1, y);
                    path << ClipperLib::IntPoint(x + 1, y + 1);
                    path << ClipperLib::IntPoint(x, y + 1);
                    clipper.AddPath(path, ClipperLib::ptSubject, true);
                }
            }
        }
        
        free(rawData);
        
        ClipperLib::Paths intermediateSolution;
        if (!clipper.Execute(ClipperLib::ctUnion, intermediateSolution, ClipperLib::pftNonZero, ClipperLib::pftNonZero)) {
            NSLog(@"Failed to union paths.");
            return 1;
        }
        
        for (ClipperLib::Paths::iterator it = intermediateSolution.begin(); it != intermediateSolution.end(); ++it) {
            if (!Orientation(*it)) {
                std::reverse(it->begin(), it->end());
            }
        }
        
        clipper.Clear();
        clipper.AddPaths(intermediateSolution, ClipperLib::ptSubject, true);
        ClipperLib::Paths solution;
        if (!clipper.Execute(ClipperLib::ctUnion, solution, ClipperLib::pftNonZero, ClipperLib::pftNonZero)) {
            NSLog(@"Failed to deep union paths.");
            return 1;
        }
        
        NSMutableArray *geometries = [NSMutableArray array];
        
        for (ClipperLib::Paths::iterator it = solution.begin(); it != solution.end(); ++it) {
            NSMutableArray *linearRingCoordinates = [NSMutableArray array];
            
            ClipperLib::Path path = *it;
            for (ClipperLib::Path::iterator it = path.begin(); it != path.end(); ++it) {
                [linearRingCoordinates addObject:@[ @(it->X), @(it->Y) ]];
            }
            [linearRingCoordinates addObject:@[ @(path.begin()->X), @(path.begin()->Y) ]];
            
            NSDictionary *polygonCoordinates = @{
                                                 @"type": @"Polygon",
                                                 @"coordinates": @[ linearRingCoordinates ],
                                                 };
            [geometries addObject:polygonCoordinates];
        }
        
        NSDictionary *result = @{
                                 @"type": @"GeometryCollection",
                                 @"geometries": geometries,
                                 };
        
        [[NSJSONSerialization dataWithJSONObject:result options:0 error:nil] writeToFile:@"/dev/stdout" atomically:NO];
        return 0;
    }
}
