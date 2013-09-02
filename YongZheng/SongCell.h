//
//  SongCell.h
//  YongZheng
//
//  Created by Kevin Zhao on 13-1-28.
//  Copyright (c) 2013年 Kevin Zhao. All rights reserved.
//

#import <UIKit/UIKit.h>

@interface SongCell : UITableViewCell

@property (nonatomic, strong) IBOutlet UILabel *songNumber;
@property (nonatomic, strong) IBOutlet UILabel *songTitle;
@property (nonatomic, strong) IBOutlet UILabel *playLength;

@end
