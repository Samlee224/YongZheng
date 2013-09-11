//
//  SongCell.h
//  YongZheng
//
//  Created by Kevin Zhao on 13-1-28.
//  Copyright (c) 2013年 Kevin Zhao. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "DACircularProgressView.h"

@interface SongCell : UITableViewCell

@property (nonatomic, strong) IBOutlet UILabel      *songNumber;
@property (nonatomic, strong) IBOutlet UILabel      *lbl_songTitle;
@property (nonatomic, strong) IBOutlet UILabel      *lbl_playbackDuration;
@property (nonatomic, strong) IBOutlet UILabel      *lbl_downloadStatus;
@property (nonatomic, strong) IBOutlet UIButton     *bt_downloadOrPause;
@property (nonatomic, strong) IBOutlet UIImageView  *img_playingStatus;
@property (nonatomic, strong) IBOutlet DACircularProgressView
                                                    *cirProgView_downloadProgress;

@end
