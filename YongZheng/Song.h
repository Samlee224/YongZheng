//
//  Song.h
//  YongZheng
//
//  Created by Kevin Zhao on 13-1-28.
//  Copyright (c) 2013年 Kevin Zhao. All rights reserved.
//

#import <Foundation/Foundation.h>


typedef enum
{
    SongStatusWaitforDownload   = 0,
    SongStatusReadytoPlay       = 1,
    SongStatusisPlaying         = 2,
    SongStatusisPaused          = 3,
    SongStatusisDownloading     = 4,
    SongStatusinDownloadQueue   = 5,
}SongStatus;


@interface Song : NSObject

@property (nonatomic, strong) NSString *songNumber;
@property (nonatomic, strong) NSString *title;
@property (nonatomic, strong) NSString *duration;
@property (nonatomic, strong) NSString *s3Url;
@property (nonatomic, strong) NSString *fileName;
@property (nonatomic, assign) SongStatus songStatus;

@end
