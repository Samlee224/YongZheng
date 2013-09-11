 //
//  SonglistViewController.m
//  YongZheng
//
//  Created by Kevin Zhao on 13-1-12.
//  Copyright (c) 2013年 Kevin Zhao. All rights reserved.
//  Test

#import "SonglistViewController.h"
#import "SongCell.h"
#import "Song.h"
#import "DACircularProgressView.h"

#define LBL_SONGTITLE       1
#define LBL_DOWNLOADSTATUS  2
#define LBL_Duration        3
#define BT_DOWNLOAD         4
#define BT_PAUSE            5

@interface SonglistViewController ()

- (NSString *)calculateDuration:(NSTimeInterval) duration;
- (void)initializeSongs;
- (void)kProgressSlider:(NSTimer*)timer;
- (IBAction)onUISliderValueChanged:(UISlider *)sender;
- (void)fileDownload:(NSIndexPath *)indexPath;
- (void)onDownloadButtonClicked: (id) sender;
- (void)onPauseDownloadButtonClicked: (id) sender;
- (void)playOrResumeSong: (NSIndexPath *)indexPath
                      At: (NSTimeInterval)time;
- (void)pauseSong: (NSIndexPath *)indexPath;
- (void)configureNowPlayingInfo: (float) elapsedPlaybackTime;

@end 
			
@implementation SonglistViewController
@synthesize tableView;
@synthesize songs;
@synthesize player;
@synthesize ProgressSlider;
@synthesize currentProgress;

@synthesize songDurationinHour, songDurationinMinute, songDurationinSecond;

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    //1. Check plist existing in Document directory, if not copy it from resource directory
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    bundleDocumentDirectoryPath = [paths objectAtIndex:0];
    
    NSString *writableDBPath= [bundleDocumentDirectoryPath stringByAppendingPathComponent:@"PlayList.plist"];
    BOOL success = [fileManager fileExistsAtPath:writableDBPath];
    if (!success)
    {
        //Copy PlayList.plist from resource path
        NSString *defaultDBPath = [[[NSBundle mainBundle] resourcePath] stringByAppendingPathComponent:@"PlayList.plist"];
        [fileManager copyItemAtPath:defaultDBPath toPath:writableDBPath error:nil];
    }
    
    //Read "PlayList.plist" to prepare create UITableview
    [self initializeSongs];
    
    //2. Initialize httpClient
    NSURL *url = [NSURL URLWithString:@"http://aws.amazon.com"];
    httpClient = [[AFHTTPClient alloc]initWithBaseURL:url];
    httpClient.operationQueue.maxConcurrentOperationCount = 2;
    
    //3. Read for stored progress for last play
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    storedProgress = [ud objectForKey:@"storedProgress"];
    storedTrack = [ud objectForKey:@"storedTrack"];
    
    //4. Setup Audio Session for Background Playback
    AVAudioSession *audioSession = [AVAudioSession sharedInstance];
    [audioSession setCategory:AVAudioSessionCategoryPlayback error:nil];
    [audioSession setActive:YES error:nil];
    
    //5. Customized progress indicator
    UIImage *progressBarImage = [UIImage imageNamed:@"progressBar.png"];
    [ProgressSlider setThumbImage:progressBarImage forState:UIControlStateNormal];
    [[UIApplication sharedApplication] beginReceivingRemoteControlEvents];
    
    downloadQueue = [[NSMutableDictionary alloc]init];
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    [[UIApplication sharedApplication]beginReceivingRemoteControlEvents];
    [self becomeFirstResponder];
}

- (BOOL)becomeFirstResponder
{
    return YES;
}

- (void)viewWillDisappear:(BOOL)animated
{
    [super viewWillDisappear:animated];
    [[UIApplication sharedApplication]endReceivingRemoteControlEvents];
    [self resignFirstResponder];
}

- (void) remoteControlReceivedWithEvent:(UIEvent *)event
{
    if (event.type == UIEventTypeRemoteControl) {
        switch (event.subtype) {
            case UIEventSubtypeRemoteControlTogglePlayPause:
                {
                    if (player.isPlaying) {
                        [self pauseSong:currentPlayingIndexPath];
                    }
                    else{
                        [self playOrResumeSong:currentPlayingIndexPath At:currentProgress];
                    }
                break;
                }
            case UIEventSubtypeRemoteControlPause:
            {
                [self pauseSong:currentPlayingIndexPath];
                break;
            }
                
            case UIEventSubtypeRemoteControlPlay:
            {
                [self playOrResumeSong:currentPlayingIndexPath At:0];
                break;
            }
            case UIEventSubtypeRemoteControlPreviousTrack:
            {
                NSIndexPath *previousIndexPath = [NSIndexPath indexPathForRow:(currentPlayingIndexPath.row-1) inSection:0];
                [self playOrResumeSong:previousIndexPath At:0];
                break;
            }
            case UIEventSubtypeRemoteControlNextTrack:
            {
                NSIndexPath *nextIndexPath = [NSIndexPath indexPathForRow:(currentPlayingIndexPath.row+1) inSection:0];
                [self playOrResumeSong:nextIndexPath At:0];
                break;
            }
            default:
                break;
        }
    }
}

- (void)initializeSongs
{
    self.songs = [[NSMutableArray alloc]init];
    
    NSString *plistPath = [bundleDocumentDirectoryPath stringByAppendingString:@"/PlayList.plist"];
    NSDictionary *dictionary = [[NSDictionary alloc] initWithContentsOfFile:plistPath];
    
    for (int i = 1; i< dictionary.count; i++) {
        
        Song* song = [[Song alloc]init];
        song.songNumber = [NSString stringWithFormat:@"%d", i];
        
        NSDictionary *songDic = [dictionary objectForKey:song.songNumber];
        song.title = [NSString stringWithFormat:@"%@", [songDic objectForKey:@"Title"]];
        song.duration = [NSString stringWithFormat:@"%@", [songDic objectForKey:@"Duration"]];
        song.s3Url = [NSString stringWithFormat:@"%@", [songDic objectForKey:@"S3Url"]];
        
        if (i < 3) {
            song.fileName = [[NSBundle mainBundle] pathForResource:song.songNumber ofType:@"mp3"];
        }
        else
        {
            NSArray *paths = NSSearchPathForDirectoriesInDomains(NSLibraryDirectory, NSUserDomainMask, YES);
            NSString *path = [paths objectAtIndex:0];
            song.fileName = [path stringByAppendingFormat:@"/%@.mp3", song.songNumber];
        }
        
        song.songStatus = SongStatusWaitforDownload;
        
        [self.songs addObject:song];
    }
}

- (void)fileDownload:(NSIndexPath *)indexPath
{
    Song *song = [songs objectAtIndex:indexPath.row];
    NSURL *url = [NSURL URLWithString:song.s3Url];
    SongCell *cell = (SongCell*)[tableView cellForRowAtIndexPath:indexPath];
    
    //1. Create Request
    NSMutableURLRequest *request = [[NSMutableURLRequest alloc]initWithURL:url];
    
    //3. Create download operation and store metadata
    AFHTTPRequestOperation *operation = [[AFHTTPRequestOperation alloc]initWithRequest:request];
    operation.userInfo = [[NSMutableDictionary alloc]init];
    [operation.userInfo setValue:indexPath forKey:@"indexPath"];
    
    song.songStatus = SongStatusisDownloading;
    
    //4. Set file path for store downloaded file
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSLibraryDirectory, NSUserDomainMask, YES);
    NSString *path = [paths objectAtIndex:0];
    NSString *fileName = [NSString stringWithFormat:@"/%d.mp3", (indexPath.row + 1)];
    NSString *filePath = [path stringByAppendingString:fileName];
    
    operation.outputStream = [NSOutputStream outputStreamToFileAtPath:filePath append:NO];
    
    //5. Update UI
    cell.bt_downloadOrPause.hidden = YES;
    cell.cirProgView_downloadProgress.hidden = NO;
    cell.lbl_downloadStatus.text = @"准备下载";
    
    [cell.bt_downloadOrPause setImage:[UIImage imageNamed:@"downloadProgressButtonPause.png"] forState:UIControlStateNormal];
    [cell.bt_downloadOrPause addTarget:self action:@selector(onPauseDownloadButtonClicked:) forControlEvents:UIControlEventTouchUpInside];
    
    //6. Add download request to download queue
    [httpClient enqueueHTTPRequestOperation:operation];
    
    [downloadQueue setValue:operation forKey:[NSString stringWithFormat:@"%d", indexPath.row]];
    
    //Download complete block
    [operation setCompletionBlockWithSuccess:^(AFHTTPRequestOperation *operation, id responseObject)
    {
        //There is a possibility, the cell address had already changed since user may scroll during the downlaod
        //So, we need to re allocate the cell;
        SongCell *cell = (SongCell*)[tableView cellForRowAtIndexPath:indexPath];
        
        cell.cirProgView_downloadProgress.hidden = YES;
        
        //Add Duration Label
        cell.lbl_downloadStatus.text = @"下载完成";
        
        NSArray *paths = NSSearchPathForDirectoriesInDomains(NSLibraryDirectory, NSUserDomainMask, NO);
        NSString *path = [paths objectAtIndex:0];
        NSString *fileName = [NSString stringWithFormat:@"/%d.mp3", (indexPath.row + 1)];
        NSString *filePath = [path stringByAppendingString:fileName];
        
        AVAudioPlayer *tempPlayer = [[AVAudioPlayer alloc]initWithContentsOfURL:
                                     [[NSURL alloc]initFileURLWithPath:filePath] error:nil];
        
        cell.lbl_playbackDuration.text = [self calculateDuration:tempPlayer.duration];
        
        song.s3Url = @"(null)";
        song.duration = cell.lbl_playbackDuration.text;
        
        NSString *plistPath = [bundleDocumentDirectoryPath stringByAppendingString:@"/PlayList.plist"];
        NSMutableDictionary *dictionary = [[NSMutableDictionary alloc] initWithContentsOfFile:plistPath];
        
        NSMutableDictionary *songArray = [dictionary objectForKey:song.songNumber];
        
        [songArray setObject:song.s3Url forKey:@"S3Url"];
        [songArray setObject:song.duration forKey:@"Duration"];
        //[songArray setObject:song.fileName forKey:@"FileName"];
        
        [dictionary writeToFile:plistPath atomically:NO];
    }
    //Failed
    failure:
     ^(AFHTTPRequestOperation *operation, NSError *error)
    {
        //[(DreamAppAppDelegate *)[[UIApplication sharedApplication] delegate] setNetworkActivityIndicatorVisible: NO];
        
        if (downloadPausedCount > 0) {
            cell.lbl_downloadStatus.text = @"下载取消";
        }
        else
        {
            cell.lbl_downloadStatus.text = @"下载失败";
        }
        
        cell.cirProgView_downloadProgress.hidden = NO;
        cell.bt_downloadOrPause.hidden = NO;
        
    }];
    //Progress updating
    [operation setDownloadProgressBlock:^(NSUInteger bytesRead, long long totalBytesRead, long long totalBytesExpectedToRead)
    {
        //There is a possibility, the cell address had already changed since user may scroll during the downlaod
        //So, we need to re allocate the cell;
        SongCell *cell = (SongCell*)[tableView cellForRowAtIndexPath:indexPath];
        
        float progress = (float)(int)totalBytesRead/(float)(int)totalBytesExpectedToRead;
        
        //Update progress
        for(UIView *oneView in cell.contentView.subviews)
        {
            if ([oneView isMemberOfClass:[DACircularProgressView class]])
            {
                DACircularProgressView * _progressIndicator = (DACircularProgressView *)oneView;
                _progressIndicator.progress = progress;
                
                cell.lbl_downloadStatus.text = [NSString stringWithFormat: @"%d KB/%d KB", (int)totalBytesRead/1024, (int)totalBytesExpectedToRead/1024];
            }
        }
    }];
    
}

- (NSString *)calculateDuration:(NSTimeInterval) duration
{
    //Hour
    self.songDurationinHour = floor(duration/60/60);
    NSString *hour = [NSString stringWithFormat:@"%d", songDurationinHour];
    
    //Minute
    self.songDurationinMinute = floor(duration/60 - songDurationinHour * 60);
    
    NSString *minute;;
    if (songDurationinMinute<10) {
        minute = [[NSString alloc] initWithFormat:@"0%d", songDurationinMinute];
    }
    else{
        minute = [[NSString alloc] initWithFormat:@"%d", songDurationinMinute];
    }
    
    //Second
    self.songDurationinSecond = round(duration - songDurationinHour * 60 * 60 - songDurationinMinute * 60);
    
    NSString *second;
    if (songDurationinSecond<10) {
        second = [[NSString alloc]initWithFormat:@"0%d", songDurationinSecond];
    }
    else{
        second = [[NSString alloc]initWithFormat:@"%d", songDurationinSecond];
    }
    
    return [NSString stringWithFormat:@"%@:%@:%@", hour, minute, second];
    
}

-(void)onDownloadButtonClicked: (id)sender
{
    AFNetworkReachabilityStatus currentNetWorkStatus = httpClient.networkReachabilityStatus;
    
    //Network Error
    if (currentNetWorkStatus == AFNetworkReachabilityStatusNotReachable) {
        UIAlertView *alert = [[UIAlertView alloc]initWithTitle:@"网络异常" message:@"当前网络无法连接" delegate:nil cancelButtonTitle:@"OK" otherButtonTitles: nil];
        
        [alert show];
        return;
        
    }
    //3G network connected
    if (currentNetWorkStatus == AFNetworkReachabilityStatusReachableViaWWAN) {
        
        UIAlertView *alert = [[UIAlertView alloc]initWithTitle:@"选择网络" message:@"是否使用3G网络下载资源，会产生流量" delegate:self cancelButtonTitle:@"取消" otherButtonTitles:@"使用", nil];
        
        [alert show];
    }
    
    if (currentNetWorkStatus == AFNetworkReachabilityStatusReachableViaWiFi) {
        SongCell* cell =(SongCell*) [[[sender superview] superview]superview];
        currentDownloadIndexPath = [tableView indexPathForCell:cell];
        
        [self fileDownload:currentDownloadIndexPath];
    }
}

- (void)onPauseDownloadButtonClicked: (id) sender
{
    SongCell *cell =(SongCell*) [[[sender superview] superview] superview];
    
    NSIndexPath *pausedIndexPath = [tableView indexPathForCell:cell];
    
    AFHTTPRequestOperation * operation = [downloadQueue valueForKey:[NSString stringWithFormat:@"%d", pausedIndexPath.row]];
    
    downloadPausedCount++;
    
    [operation cancel];
}


- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
}

- (NSInteger) tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    return self.songs.count;
}


-(UITableViewCell *) tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    Song *song = [self.songs objectAtIndex:indexPath.row];
    SongCell *songCell = [self.tableView dequeueReusableCellWithIdentifier:@"SongCell"];
    
    if (indexPath.row % 2) {
    
        [songCell setBackgroundColor:[UIColor whiteColor]];
    }
    else
    {
        [songCell setBackgroundColor:[UIColor lightGrayColor]];
    }
    
    songCell.lbl_songTitle.text = song.title;
    
    switch (song.songStatus) {
        case SongStatusReadytoPlay:
        {
            songCell.lbl_playbackDuration.hidden = NO;
            songCell.lbl_playbackDuration.text = song.duration;
            break;
        }
        case SongStatusWaitforDownload:
        {
            songCell.bt_downloadOrPause.hidden = NO;
            [songCell.bt_downloadOrPause addTarget:self action:@selector(onDownloadButtonClicked) forControlEvents:UIControlEventTouchUpInside];
            break;
        }
            
        case SongStatusisPaused:
        {
            songCell.img_playingStatus.hidden = NO;
            [songCell.img_playingStatus setImage:[UIImage imageNamed:@"NowPlayingPauseControl~iphone.png"]];
            break;
        }
        case SongStatusisPlaying:
        {
            songCell.img_playingStatus.hidden = NO;
            [songCell.img_playingStatus setImage:[UIImage imageNamed:@"nowPlayingGlyph.png"]];
            break;
        }
        case SongStatusisDownloading:
        {
            songCell.cirProgView_downloadProgress.hidden = NO;
            songCell.bt_downloadOrPause.hidden = NO;
            
            [songCell.bt_downloadOrPause setImage:[UIImage imageNamed:@"downloadProgressButtonPause.png"] forState:UIControlStateNormal];
            [songCell.bt_downloadOrPause addTarget:self action:@selector(onPauseDownloadButtonClicked:) forControlEvents:UIControlEventTouchUpInside];
            break;
        }
        default:
            break;
    }
    return songCell;
}

-(void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    //Same Cell
    if ([indexPath isEqual:currentPlayingIndexPath]) {
        if (player.isPlaying) {
            [self pauseSong:indexPath];
        }
        else
        {
            [self playOrResumeSong:indexPath At:currentProgress];
        }
    }
    //Different Cell
    else
    {
        [self playOrResumeSong:indexPath At:0];
    }
}




- (void)kProgressSlider:(NSTimer*)timer
{
    self.ProgressSlider.value += 0.01;
    timerInterval++;

    if (timerInterval == 100) {
        timerInterval = 0;
        self.currentProgress++;
        
        self.lbl_currentProgress.text = [self calculateDuration:self.currentProgress];
        self.lbl_songLength.text = [NSString stringWithFormat:@"-%@",[self calculateDuration:(player.duration - self.currentProgress)]];
    }
    
}



- (void) pauseSong:(NSIndexPath *)indexPath
{
    [playbackTimer invalidate];
    [player pause];
    
    currentProgress = player.currentTime;
    
    SongCell *cell = (SongCell*)[self.tableView cellForRowAtIndexPath:currentPlayingIndexPath];
    [cell.img_playingStatus setImage:[UIImage imageNamed:@"NowPlayingPauseControl~iphone.png"]];
    
    //Update songPlaybackStatus to Paused
    Song *song = [self.songs objectAtIndex:indexPath.row];
    song.songStatus = SongStatusisPaused;
}


- (void) playOrResumeSong:(NSIndexPath *)indexPath
                       At:(NSTimeInterval)time
{
    [player stop];
    [playbackTimer invalidate];
    
    Song *previousSong = [self.songs objectAtIndex:currentPlayingIndexPath.row];
    previousSong.songStatus = SongStatusReadytoPlay;
    SongCell *previousCell = (SongCell*)[self.tableView cellForRowAtIndexPath:currentPlayingIndexPath];
    
    previousCell.img_playingStatus.hidden = YES;
    
    Song *song= [self.songs objectAtIndex:indexPath.row];
    //storedTrack = [NSNumber numberWithInt:indexPath.row];
    //currentDownloadIndexPath = indexPath;
    //NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    //[ud setObject:storedTrack forKey:@"storedTrack"];
    //[ud synchronize];
    
    
    //if song is downloaded than play, otherwize show popup and notice to download.
    if (![song.s3Url isEqual: @"(null)"])
    {
        //NSData *fileUrl=[[NSData alloc]initWithContentsOfURL:[NSURL URLWithString:song.s3Url]];
        
        //self.player = [[AVAudioPlayer alloc]initWithData:fileUrl error:nil];
        
        //[self.player play];
        
        //NSURL *url = [NSURL URLWithString:song.s3Url];
        
        //NSData *data = [NSData dataWithContentsOfURL:url];
        
        //self.player = [[AVAudioPlayer alloc] initWithData:data error:nil];
    }
    else
    {
        self.player = [[AVAudioPlayer alloc]initWithContentsOfURL:
                       [[NSURL alloc]initFileURLWithPath:song.fileName] error:nil];
        
        [self.player setDelegate:self];
        
        player.currentTime = time;
        [self.player play];
        
        song.songStatus = SongStatusisPlaying;
        
        //Store currently playing indexPath
        currentPlayingIndexPath = indexPath;
        
        SongCell *cell = (SongCell*)[self.tableView cellForRowAtIndexPath:currentPlayingIndexPath];
        cell.img_playingStatus.hidden = NO;
        [cell.img_playingStatus setImage:[UIImage imageNamed:@"nowPlayingGlyph.png"]];
        
        //Update Progress Slider
        self.currentProgress = time;
        playbackTimer = [NSTimer scheduledTimerWithTimeInterval:0.01
                                                      target:self
                                                    selector:@selector(kProgressSlider:)
                                                    userInfo:nil repeats:YES];
        
        self.ProgressSlider.maximumValue = player.duration;
        self.ProgressSlider.value = currentProgress;
        self.lbl_songLength.text =[NSString stringWithFormat:@"-%@",[self calculateDuration:player.duration]];
        self.lbl_currentProgress.text = [self calculateDuration:player.currentTime];
        
        [self configureNowPlayingInfo:0.0];
    }

}


- (IBAction)onUISliderValueChanged:(UISlider *)sender {
    
    float value = sender.value;
    player.currentTime = value;
    self.currentProgress = value;
    
    [self configureNowPlayingInfo:value];
}

- (IBAction)onDownloadAllButtonPressed:(id)sender
{
    for(Song *song in self.songs)
    {
        if (![song.s3Url isEqual: @"(null)"])
        {
            NSIndexPath *indexPath = [NSIndexPath indexPathForRow:([song.songNumber integerValue] - 1) inSection:0];
            [self fileDownload:indexPath];
        }
    }
}

- (void) configureNowPlayingInfo:(float)elapsedPlaybackTime
{
    Song *song= [self.songs objectAtIndex:currentPlayingIndexPath.row];
    
    //Set Information for Nowplaying Info Center
    if (NSClassFromString(@"MPNowPlayingInfoCenter")) {
        NSMutableDictionary * dict = [[NSMutableDictionary alloc] init];
        [dict setObject:song.title forKey:MPMediaItemPropertyAlbumTitle];
        [dict setObject:@"王玥波" forKey:MPMediaItemPropertyArtist];
        [dict setObject:[NSNumber numberWithInteger:player.duration] forKey:MPMediaItemPropertyPlaybackDuration];
        [dict setObject:[NSNumber numberWithInteger:elapsedPlaybackTime] forKey:MPNowPlayingInfoPropertyElapsedPlaybackTime];
        [dict setObject:[NSNumber numberWithInteger:1.0] forKey:MPNowPlayingInfoPropertyPlaybackRate];
        [dict setObject:[NSNumber numberWithInteger:2] forKey:MPMediaItemPropertyAlbumTrackCount];
        
        UIImage *img = [UIImage imageNamed: @"wangyuebo.jpg"];
        MPMediaItemArtwork * mArt = [[MPMediaItemArtwork alloc] initWithImage:img];
        [dict setObject:mArt forKey:MPMediaItemPropertyArtwork];
        [[MPNowPlayingInfoCenter defaultCenter] setNowPlayingInfo:dict];
        
    }
}

/*****************************************************************************************/
/* AVAudioPlayerDelegate */
- (void)audioPlayerDidFinishPlaying:(AVAudioPlayer *)player successfully:(BOOL)flag;
{
    //Stop timer
    [playbackTimer invalidate];

    //Play next song
    NSIndexPath *indexPathofNextSong = [NSIndexPath indexPathForRow:(currentPlayingIndexPath.row+1) inSection:0];

    [self playOrResumeSong:indexPathofNextSong At:0];
    
}

- (void)audioPlayerBeginInterruption:(AVAudioPlayer *)player;
{
    [self pauseSong:currentPlayingIndexPath];
}

- (void)audioPlayerEndInterruption:(AVAudioPlayer *)player withOptions:(NSUInteger)flags
{
    [self playOrResumeSong:currentPlayingIndexPath At:currentProgress];
}
/*****************************************************************************************/

- (void)alertView:(UIAlertView *)alertView clickedButtonAtIndex:(NSInteger)buttonIndex
{
    //Button OK
    if (buttonIndex == 1) {
        [self fileDownload:currentDownloadIndexPath];
    }
    else
    {
        //Do nothing
    }
}

@end
