//
//  SongCell.m
//  YongZheng
//
//  Created by Kevin Zhao on 13-1-28.
//  Copyright (c) 2013年 Kevin Zhao. All rights reserved.
//

#import "SongCell.h"

@implementation SongCell

@synthesize songNumber;
@synthesize songTitle;
@synthesize playLength;

- (id)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier
{
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self) {
        // Initialization code
    }
    return self;
}

- (void)setSelected:(BOOL)selected animated:(BOOL)animated
{
    [super setSelected:selected animated:animated];

    // Configure the view for the selected state
}

@end
