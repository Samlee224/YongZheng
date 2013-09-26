//
//  SonglistViewController.h
//  YongZheng
//
//  Created by Kevin Zhao on 13-1-12.
//  Copyright (c) 2013年 Kevin Zhao. All rights reserved.
//

#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <AudioToolbox/AudioToolbox.h>
#import <MediaPlayer/MediaPlayer.h>
#import <CoreMedia/CMTime.h>
#import <QuartzCore/QuartzCore.h>
#import "AFHTTPClient.h"
#import "AFHTTPRequestOperation.h"
#import "DACircularProgressView.h"
#import "DreamAppAppDelegate.h"

@interface SonglistViewController: UIViewController <AVAudioPlayerDelegate, UIAlertViewDelegate>
{
    UIImageView     *imageView;
    UITableView     *tableView;
    AFHTTPClient    *httpClient;
    NSMutableDictionary  *downloadQueue;
    
    NSString        *bundleDocumentDirectoryPath;
    
    NSInteger       currentProgress;
    NSInteger       timerInterval;
    
    NSInteger       songDurationinHour;
    NSInteger       songDurationinMinute;
    NSInteger       songDurationinSecond;
    
    NSNumber        *storedTrack;
    NSNumber        *storedProgress;
    
    NSTimer         *playbackTimer;
    
    NSIndexPath     *currentDownloadIndexPath;
    NSIndexPath     *currentPlayingIndexPath;

    NSInteger       downloadPausedCount;
}

@property (nonatomic, retain) NSMutableArray* songs;

@property (nonatomic, retain) IBOutlet UITableView *tableView;
@property (nonatomic,retain) IBOutlet UISlider *ProgressSlider;

@property (nonatomic, retain) AVAudioPlayer *player;
@property (nonatomic) NSInteger songDurationinHour;
@property (nonatomic) NSInteger songDurationinMinute;
@property (nonatomic) NSInteger songDurationinSecond;
@property (nonatomic) NSInteger currentProgress;
@property (nonatomic, retain) NSTimer *timer;

@property (retain, nonatomic) IBOutlet UILabel *lbl_currentProgress;
@property (retain, nonatomic) IBOutlet UILabel *lbl_songLength;
@property (retain, nonatomic) IBOutlet UIButton *bt_downloadAll;

- (IBAction)onUISliderValueChanged:(UISlider *)sender;
- (IBAction)onDownloadButtonClicked:(id)sender;
- (IBAction)onDownloadAllButtonPressed:(id)sender;

@end
