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

@interface SonglistViewController ()

- (NSString *)calculateDuration:(NSTimeInterval) duration;
- (void)initializeSongs;
- (void)updateProgressSlider:(NSTimer*)timer;
- (IBAction)onUISliderValueChanged:(UISlider *)sender;
- (void)fileDownload:(NSIndexPath *)indexPath;
- (IBAction)onDownloadButtonClicked: (id) sender;
- (void)onPauseDownloadButtonClicked: (id) sender;
- (void)playOrResumeSong: (NSIndexPath *)indexPath At: (NSTimeInterval)time;
- (void)pauseSong: (NSIndexPath *)indexPath;
- (void)configureNowPlayingInfo: (float) elapsedPlaybackTime;
- (void)onPauseDownloadAllButtonPressed:(id)sender;

@end
			
@implementation SonglistViewController
@synthesize tableView;
@synthesize songs;
@synthesize player;
@synthesize ProgressSlider;
@synthesize currentPlayingProgress;
@synthesize currentPlayingIndexPath;
@synthesize bt_downloadAll;

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
    storedPlayingIndexPath = [NSIndexPath indexPathForRow:([[ud objectForKey:@"storedTrack"] intValue]-1) inSection:0];
    storedPlayingProgress = [[ud objectForKey:@"storedProgress"] intValue];
    
    if (storedPlayingProgress >= 30) {
        storedPlayingProgress = storedPlayingProgress - 30;
    }
    
    if ([[ud objectForKey:@"storedTrack"] intValue] != 0) {
        [self playOrResumeSong:storedPlayingIndexPath At:storedPlayingProgress];
    }
    
    //4. Setup Audio Session for Background Playback
    AVAudioSession *audioSession = [AVAudioSession sharedInstance];
    [audioSession setCategory:AVAudioSessionCategoryPlayback error:nil];
    [audioSession setActive:YES error:nil];
    
    //5. Customized progress indicator
    float version = [[[UIDevice currentDevice] systemVersion] floatValue];
    
    if (version >= 7.0)
    {
        UIImage *progressBarImage = [UIImage imageNamed:@"progressBar.png"];
        [ProgressSlider setThumbImage:progressBarImage forState:UIControlStateNormal];
        
        bt_downloadAll.layer.borderWidth = 1.0;
        [bt_downloadAll.layer setCornerRadius:8.];
        bt_downloadAll.layer.borderColor = [bt_downloadAll.titleLabel.textColor CGColor];
    }

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

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
}

- (void)remoteControlReceivedWithEvent:(UIEvent *)event
{
    if (event.type == UIEventTypeRemoteControl) {
        switch (event.subtype) {
            case UIEventSubtypeRemoteControlTogglePlayPause:
                {
                    if (player.isPlaying) {
                        [self pauseSong:currentPlayingIndexPath];
                    }
                    else{
                        [self playOrResumeSong:currentPlayingIndexPath At:currentPlayingProgress];
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
    
    for (int i = 1; i<= dictionary.count; i++)
    {
        Song* song = [[Song alloc]init];
        song.songNumber = [NSString stringWithFormat:@"%d", i];
        
        NSDictionary *songDic = [dictionary objectForKey:song.songNumber];
        song.title = [NSString stringWithFormat:@"%@", [songDic objectForKey:@"Title"]];
        song.duration = [NSString stringWithFormat:@"%@", [songDic objectForKey:@"Duration"]];
        song.s3Url = [NSString stringWithFormat:@"%@", [songDic objectForKey:@"S3Url"]];
        
        if (i < 3) {
            song.fileName = [[NSBundle mainBundle] pathForResource:song.songNumber ofType:@"mp3"];
            song.songStatus = SongStatusReadytoPlay;
        }
        else
        {
            NSArray *paths = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES);
            NSString *path = [paths objectAtIndex:0];
            song.fileName = [path stringByAppendingFormat:@"/%@.mp3", song.songNumber];
            
            NSFileManager *fileManager = [NSFileManager defaultManager];
            if([fileManager fileExistsAtPath:song.fileName])
            {
                song.songStatus = SongStatusReadytoPlay;
            }
            else
            {
                song.songStatus = SongStatusWaitforDownload;
            }
        }
        
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
    
    song.songStatus = SongStatusinDownloadQueue;
    
    //4. Set file path for store downloaded file
    NSString *path = NSTemporaryDirectory();
    NSString *fileName = [NSString stringWithFormat:@"%d.mp3", (indexPath.row + 1)];
    NSString *filePath = [path stringByAppendingString:fileName];
    
    operation.outputStream = [NSOutputStream outputStreamToFileAtPath:filePath append:NO];
    
    if (cell) {
        //5. Update UI
        cell.cirProgView_downloadProgress.progress = 0;
        cell.cirProgView_downloadProgress.hidden = NO;
        cell.cirProgView_downloadProgress.progressTintColor = [UIColor blueColor];
        cell.lbl_songStatus.text = @"等待下载";
        
        [cell.bt_downloadOrPause removeTarget:self action:@selector(onDownloadButtonClicked:) forControlEvents:UIControlEventTouchUpInside];
        [cell.bt_downloadOrPause setBackgroundImage:[UIImage imageNamed:@"downloadProgressButtonPause.png"] forState:UIControlStateNormal];
        [cell.bt_downloadOrPause addTarget:self action:@selector(onPauseDownloadButtonClicked:) forControlEvents:UIControlEventTouchUpInside];
    }
    
    //6. Add download request to download queue
    [httpClient enqueueHTTPRequestOperation:operation];
    
    [downloadQueue setValue:operation forKey:[NSString stringWithFormat:@"%d", indexPath.row]];
    
    //Download complete block
    [operation setCompletionBlockWithSuccess:^(AFHTTPRequestOperation *operation, id responseObject)
    {
        //There is a possibility, the cell address had already changed since user may scroll during the downlaod
        //So, we need to re allocate the cell;
        SongCell *cell = (SongCell*)[tableView cellForRowAtIndexPath:indexPath];
        
        //Copy from temp directory to Library Directory
        NSString *path = NSTemporaryDirectory();
        
        NSString *fileName = [NSString stringWithFormat:@"%d.mp3", (indexPath.row + 1)];
        NSString *filePath = [path stringByAppendingString:fileName];
        
        NSArray *despaths = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES);
        NSString *despath = [despaths objectAtIndex:0];
        NSString *desfileName = [NSString stringWithFormat:@"/%d.mp3", (indexPath.row + 1)];
        NSString *desfilePath = [despath stringByAppendingString:desfileName];
        
        NSFileManager *fileManager = [NSFileManager defaultManager];
        
        [fileManager copyItemAtPath:filePath toPath:desfilePath error:nil];
        [fileManager removeItemAtPath:filePath error:nil];
        
        //Calculate duration of the song
        AVAudioPlayer *tempPlayer = [[AVAudioPlayer alloc]initWithContentsOfURL:
                                     [[NSURL alloc]initFileURLWithPath:desfilePath] error:nil];
        
        if (cell) {
            //Add Duration Label
            cell.lbl_songStatus.text = @"下载完成";
            //UI Update
            cell.cirProgView_downloadProgress.hidden = YES;
            cell.bt_downloadOrPause.hidden = YES;
            
            cell.lbl_playbackDuration.hidden = NO;
            cell.lbl_playbackDuration.text = [self calculateDuration:tempPlayer.duration];
            
        }
        
        //Write back to PlayList.plist
        song.s3Url = @"(null)";
        song.duration = [self calculateDuration:tempPlayer.duration];
        
        NSString *plistPath = [bundleDocumentDirectoryPath stringByAppendingString:@"/PlayList.plist"];
        NSMutableDictionary *dictionary = [[NSMutableDictionary alloc] initWithContentsOfFile:plistPath];
        NSMutableDictionary *songArray = [dictionary objectForKey:song.songNumber];
        
        [songArray setObject:song.s3Url forKey:@"S3Url"];
        [songArray setObject:song.duration forKey:@"Duration"];
        
        [dictionary writeToFile:plistPath atomically:NO];
        
        song.songStatus = SongStatusReadytoPlay;
        [downloadQueue removeObjectForKey:[NSString stringWithFormat:@"%ld", (long)indexPath.row]];
    }
    //Failed
    failure:
     ^(AFHTTPRequestOperation *operation, NSError *error)
    {
        SongCell *cell = (SongCell*)[tableView cellForRowAtIndexPath:indexPath];
        
        if (cell) {
            if (downloadPausedCount > 0) {
                cell.lbl_songStatus.text = @"下载取消";
            }
            else
            {
                cell.lbl_songStatus.text = @"下载失败";
            }
            
            cell.cirProgView_downloadProgress.hidden = YES;
            cell.bt_downloadOrPause.hidden = NO;
            
            
            [cell.bt_downloadOrPause setBackgroundImage:[UIImage imageNamed:@"downloadButton.png"] forState:UIControlStateNormal];
            [cell.bt_downloadOrPause removeTarget:self action:@selector(onPauseDownloadButtonClicked:) forControlEvents:UIControlEventTouchUpInside];
            [cell.bt_downloadOrPause addTarget:self action:@selector(onDownloadButtonClicked:) forControlEvents:UIControlEventTouchUpInside];
        }
    
        
        song.songStatus = SongStatusWaitforDownload;
        
        NSFileManager *fileManager = [NSFileManager defaultManager];
        
        NSString *path = NSTemporaryDirectory();
        NSString *fileName = [NSString stringWithFormat:@"%d.mp3", (indexPath.row + 1)];
        NSString *filePath = [path stringByAppendingString:fileName];
        
        [fileManager removeItemAtPath:filePath error:nil];
        
        [downloadQueue removeObjectForKey:[NSString stringWithFormat:@"%d", indexPath.row]];
        
    }];
    //Progress updating
    [operation setDownloadProgressBlock:^(NSUInteger bytesRead, long long totalBytesRead, long long totalBytesExpectedToRead)
    {
        song.songStatus = SongStatusisDownloading;
        
        //There is a possibility, the cell address had already changed since user may scroll during the downlaod
        //So, we need to re allocate the cell;
        SongCell *cell = (SongCell*)[tableView cellForRowAtIndexPath:indexPath];
        
        if (cell) {
            //Update progress
            cell.cirProgView_downloadProgress.progress = (float)(int)totalBytesRead/(float)(int)totalBytesExpectedToRead;
            cell.lbl_songStatus.text = [NSString stringWithFormat: @"%d KB/%d KB", (int)totalBytesRead/1024, (int)totalBytesExpectedToRead/1024];
        }
        
    }];
    
}

- (NSString *)calculateDuration:(NSTimeInterval) duration
{
    NSInteger songDurationinHour, songDurationinMinute, songDurationinSecond;
    
    //Hour
    songDurationinHour = floor(duration/60/60);
    NSString *hour = [NSString stringWithFormat:@"%d", songDurationinHour];
    
    //Minute
    songDurationinMinute = floor(duration/60 - songDurationinHour * 60);
    
    NSString *minute;;
    if (songDurationinMinute<10) {
        minute = [[NSString alloc] initWithFormat:@"0%d", songDurationinMinute];
    }
    else{
        minute = [[NSString alloc] initWithFormat:@"%d", songDurationinMinute];
    }
    
    //Second
    songDurationinSecond = round(duration - songDurationinHour * 60 * 60 - songDurationinMinute * 60);
    
    NSString *second;
    if (songDurationinSecond<10) {
        second = [[NSString alloc]initWithFormat:@"0%d", songDurationinSecond];
    }
    else{
        second = [[NSString alloc]initWithFormat:@"%d", songDurationinSecond];
    }
    
    return [NSString stringWithFormat:@"%@:%@:%@", hour, minute, second];
    
}

- (IBAction)onDownloadButtonClicked:(id)sender
{
    AFNetworkReachabilityStatus currentNetWorkStatus = httpClient.networkReachabilityStatus;
    
    SongCell* cell;
    
    float version = [[[UIDevice currentDevice] systemVersion] floatValue];
    
    if (version >= 7.0)
    {
        cell =(SongCell*) [[[sender superview] superview]superview];
    }
    else
    {
        cell =(SongCell*) [[sender superview] superview];
    }
    
    currentDownloadIndexPath = [tableView indexPathForCell:cell];
    
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
        [self fileDownload:currentDownloadIndexPath];
        [cell.bt_downloadOrPause removeTarget:self action:@selector(onDownloadButtonClicked:) forControlEvents:UIControlEventTouchUpInside];
        [cell.bt_downloadOrPause addTarget:self action:@selector(onPauseDownloadButtonClicked:) forControlEvents:UIControlEventTouchUpInside];
    }
}

- (void)onPauseDownloadButtonClicked: (id) sender
{
    SongCell* cell;
    
    float version = [[[UIDevice currentDevice] systemVersion] floatValue];
    
    if (version >= 7.0)
    {
        cell =(SongCell*) [[[sender superview] superview]superview];
    }
    else
    {
        cell =(SongCell*) [[sender superview] superview];
    }
    
    cell.lbl_songStatus.text = @"下载暂停";
    
    NSIndexPath *pausedIndexPath = [tableView indexPathForCell:cell];
    Song *song = [self.songs objectAtIndex:pausedIndexPath.row];
    
    if (song.songStatus == SongStatusinDownloadQueue) {
        [cell.bt_downloadOrPause setBackgroundImage:[UIImage imageNamed:@"downloadButton.png"] forState:UIControlStateNormal];
        [cell.bt_downloadOrPause removeTarget:self action:@selector(onDownloadButtonClicked:) forControlEvents:UIControlEventTouchUpInside];
        [cell.bt_downloadOrPause addTarget:self action:@selector(onPauseDownloadButtonClicked:) forControlEvents:UIControlEventTouchUpInside];
    }

    AFHTTPRequestOperation * operation = [downloadQueue valueForKey:[NSString stringWithFormat:@"%d", pausedIndexPath.row]];
    downloadPausedCount++;
    [operation cancel];
    
}

- (IBAction)onDownloadAllButtonPressed:(id)sender
{
    for(Song *song in self.songs)
    {
        if (![song.s3Url isEqual: @"(null)"])
        {
            NSIndexPath *indexPath = [NSIndexPath indexPathForRow:([song.songNumber integerValue] - 1) inSection:0];
            NSString *key = [NSString stringWithFormat:@"%d", ([song.songNumber integerValue] - 1)];
            
            AFHTTPRequestOperation *operation = [downloadQueue valueForKey:key];
            if (!operation) {
                [self fileDownload:indexPath];
            }
        }
    }
    
    [bt_downloadAll setTitle:@"全部暂停" forState:UIControlStateNormal];
    [bt_downloadAll removeTarget:self action:@selector(onDownloadAllButtonPressed:) forControlEvents:UIControlEventTouchUpInside];
    [bt_downloadAll addTarget:self action:@selector(onPauseDownloadAllButtonPressed:) forControlEvents:UIControlEventTouchUpInside];
}

- (void) onPauseDownloadAllButtonPressed:(id)sender
{
    for (NSString *key in downloadQueue)
    {
        downloadPausedCount++;
        
        AFHTTPRequestOperation *operation = [downloadQueue valueForKey:key];
        [operation cancel];
    }
    
    [bt_downloadAll setTitle:@"全部下载" forState:UIControlStateNormal];;
    [bt_downloadAll removeTarget:self action:@selector(onPauseDownloadButtonClicked:) forControlEvents:UIControlEventTouchUpInside];
    [bt_downloadAll addTarget:self action:@selector(onDownloadAllButtonPressed:) forControlEvents:UIControlEventTouchUpInside];
}


//**************************************************************************************************
//TableView delegate

- (NSInteger) tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    return self.songs.count;
}


-(UITableViewCell *) tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    Song *song = [self.songs objectAtIndex:indexPath.row];
    SongCell *songCell = [self.tableView dequeueReusableCellWithIdentifier:@"SongCell" forIndexPath:indexPath];
    
    if (indexPath.row % 2)
    {
        [songCell setBackgroundColor:[UIColor whiteColor]];
    }
    else
    {
        [songCell setBackgroundColor:[UIColor colorWithRed:.1 green:.1 blue:.1 alpha:0.0]];
    }
    
    //Clar existing content
    for (UIView* oneView in songCell.contentView.subviews) {
        oneView.hidden = YES;
    }
    
    //Configure Cell
    songCell.lbl_songTitle.hidden = NO;
    songCell.lbl_songTitle.text = song.title;
    
    songCell.lbl_songNumber.hidden = NO;
    songCell.lbl_songNumber.text = song.songNumber;
    
    switch (song.songStatus) {
        case SongStatusReadytoPlay:
        {
            songCell.lbl_playbackDuration.hidden = NO;
            songCell.lbl_playbackDuration.text = song.duration;
            
            songCell.lbl_songStatus.hidden = NO;
            songCell.lbl_songStatus.text = @"准备播放";
            
            break;
        }
        case SongStatusWaitforDownload:
        {
            songCell.bt_downloadOrPause.hidden = NO;
            [songCell.bt_downloadOrPause setBackgroundImage:[UIImage imageNamed:@"downloadButton.png"] forState:UIControlStateNormal];
            [songCell.bt_downloadOrPause removeTarget:self action:@selector(onPauseDownloadButtonClicked:) forControlEvents:UIControlEventTouchUpInside];
            [songCell.bt_downloadOrPause addTarget:self action:@selector(onDownloadButtonClicked:) forControlEvents:UIControlEventTouchUpInside];
            
            songCell.lbl_songStatus.hidden = NO;
            songCell.lbl_songStatus.text = @"等待下载";
            
            break;
        }
        case SongStatusisPaused:
        {
            songCell.img_playingStatus.hidden = NO;
            [songCell.img_playingStatus setImage:[UIImage imageNamed:@"NowPlayingPauseControl~iphone.png"]];
            
            songCell.lbl_playbackDuration.hidden = NO;
            songCell.lbl_songStatus.text = @"播放暂停";
            break;
        }
        case SongStatusisPlaying:
        {
            songCell.img_playingStatus.hidden = NO;
            [songCell.img_playingStatus setImage:[UIImage imageNamed:@"nowPlayingGlyph.png"]];
            
            songCell.lbl_playbackDuration.hidden = NO;
            songCell.lbl_playbackDuration.text = song.duration;
            
            songCell.lbl_songStatus.hidden = NO;
            songCell.lbl_songStatus.text = @"正在播放";
            break;
        }
        case SongStatusisDownloading:
        {
            songCell.cirProgView_downloadProgress.hidden = NO;
            songCell.cirProgView_downloadProgress.progressTintColor = [UIColor blueColor];
            
            songCell.bt_downloadOrPause.hidden = NO;
            [songCell.bt_downloadOrPause setBackgroundImage:[UIImage imageNamed:@"downloadProgressButtonPause.png"] forState:UIControlStateNormal];
            [songCell.bt_downloadOrPause removeTarget:self action:@selector(onDownloadButtonClicked:) forControlEvents:UIControlEventTouchUpInside];
            [songCell.bt_downloadOrPause addTarget:self action:@selector(onPauseDownloadButtonClicked:) forControlEvents:UIControlEventTouchUpInside];
            
            songCell.lbl_songStatus.hidden = NO;
            songCell.lbl_songStatus.text = @"正在下载";
            
            break;
        }
        case SongStatusinDownloadQueue:
        {
            songCell.bt_downloadOrPause.hidden = NO;
            [songCell.bt_downloadOrPause removeTarget:self action:@selector(onDownloadButtonClicked:) forControlEvents:UIControlEventTouchUpInside];
            [songCell.bt_downloadOrPause setBackgroundImage:[UIImage imageNamed:@"downloadProgressButtonPause.png"] forState:UIControlStateNormal];
            [songCell.bt_downloadOrPause addTarget:self action:@selector(onPauseDownloadButtonClicked:) forControlEvents:UIControlEventTouchUpInside];
            
            songCell.lbl_songStatus.hidden = NO;
            songCell.lbl_songStatus.text = @"等待下载";
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
            [self playOrResumeSong:indexPath At:currentPlayingProgress];
        }
    }
    //Different Cell
    else
    {
        [self playOrResumeSong:indexPath At:0];
    }
}

- (void)updateProgressSlider:(NSTimer*)timer
{
    self.ProgressSlider.value += 0.01;
    timerInterval++;

    if (timerInterval == 100) {
        timerInterval = 0;
        self.currentPlayingProgress++;
        
        self.lbl_currentProgress.text = [self calculateDuration:self.currentPlayingProgress];
        self.lbl_songLength.text = [NSString stringWithFormat:@"-%@",[self calculateDuration:(player.duration - self.currentPlayingProgress)]];
    }
    
}

- (void) pauseSong:(NSIndexPath *)indexPath
{
    [playbackTimer invalidate];
    [player pause];
    
    currentPlayingProgress = player.currentTime;
    
    SongCell *cell = (SongCell*)[self.tableView cellForRowAtIndexPath:currentPlayingIndexPath];
    [cell.img_playingStatus setImage:[UIImage imageNamed:@"NowPlayingPauseControl~iphone.png"]];
    
    //Update songPlaybackStatus to Paused
    Song *song = [self.songs objectAtIndex:indexPath.row];
    song.songStatus = SongStatusisPaused;
}


- (void) playOrResumeSong:(NSIndexPath *)indexPath At:(NSTimeInterval)time
{
    [player stop];
    [playbackTimer invalidate];
    
    Song *previousSong = [self.songs objectAtIndex:currentPlayingIndexPath.row];
    previousSong.songStatus = SongStatusReadytoPlay;
    SongCell *previousCell = (SongCell*)[self.tableView cellForRowAtIndexPath:currentPlayingIndexPath];
    
    previousCell.img_playingStatus.hidden = YES;
    
    Song *song= [self.songs objectAtIndex:indexPath.row];
    SongCell *cell = (SongCell*)[self.tableView cellForRowAtIndexPath:indexPath];
    //if song is downloaded than play, otherwize show popup and notice to download.
    if (![song.s3Url isEqual: @"(null)"])
    {
        cell.lbl_songStatus.text = @"请先下载";
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
        
        
        cell.img_playingStatus.hidden = NO;
        [cell.img_playingStatus setImage:[UIImage imageNamed:@"nowPlayingGlyph.png"]];
        
        //Update Progress Slider
        self.currentPlayingProgress = time;
        playbackTimer = [NSTimer scheduledTimerWithTimeInterval:0.01
                                                      target:self
                                                    selector:@selector(updateProgressSlider:)
                                                    userInfo:nil repeats:YES];
        
        self.ProgressSlider.maximumValue = player.duration;
        self.ProgressSlider.value = currentPlayingProgress;
        self.lbl_songLength.text =[NSString stringWithFormat:@"-%@",[self calculateDuration:player.duration]];
        self.lbl_currentProgress.text = [self calculateDuration:player.currentTime];
        
        [self configureNowPlayingInfo:0.0];
    }

}


- (IBAction)onUISliderValueChanged:(UISlider *)sender {
    
    float value = sender.value;
    player.currentTime = value;
    self.currentPlayingProgress = value;
    
    [self configureNowPlayingInfo:value];
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
    [self playOrResumeSong:currentPlayingIndexPath At:currentPlayingProgress];
}

/*****************************************************************************************/

- (void)alertView:(UIAlertView *)alertView clickedButtonAtIndex:(NSInteger)buttonIndex
{
    //Button OK
    if (buttonIndex == 1) {
        [self fileDownload:currentDownloadIndexPath];
        
        SongCell *cell = (SongCell*)[self.tableView cellForRowAtIndexPath:currentDownloadIndexPath];
        
        [cell.bt_downloadOrPause removeTarget:self action:@selector(onDownloadButtonClicked:) forControlEvents:UIControlEventTouchUpInside];
        [cell.bt_downloadOrPause addTarget:self action:@selector(onPauseDownloadButtonClicked:) forControlEvents:UIControlEventTouchUpInside];
    }
    else
    {
        //Do nothing
    }
}

@end
