//
//  Song.h
//  YongZheng
//
//  Created by Kevin Zhao on 13-1-28.
//  Copyright (c) 2013年 Kevin Zhao. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface Song : NSObject

@property (nonatomic, strong) NSString *songNumber;
@property (nonatomic, strong) NSString *title;
@property (nonatomic, strong) NSString *duration;
@property (nonatomic, strong) NSString *s3Url;
@property (nonatomic, strong) NSString *fileName;

@end
