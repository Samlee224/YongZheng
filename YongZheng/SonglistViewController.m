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
- (void)kProgressSlider:(NSTimer*)timer;
- (IBAction)onUISliderValueChanged:(UISlider *)sender;
- (void)fileDownload:(NSIndexPath *)indexPath;
- (void)removeProgressIndicatorfromcell: (NSIndexPath *) indexPath;
- (void)removeDownloadButtonfromcell:(NSIndexPath *)indexPath;
- (void)addDownloadButtontocell:(NSIndexPath *)indexPath;
- (void)addProgressIndicatortocell:(NSIndexPath *)indexPath;
- (void)onDownloadButtonClicked: (id) sender;
- (void)removeNowPlayingIndicator: (NSIndexPath *)indexPath;

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
@synthesize timer;
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
        success = [fileManager copyItemAtPath:defaultDBPath toPath:writableDBPath error:nil];
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
    success = [audioSession setActive:YES error:nil];
    
    //5. Customized progress indicator
    UIImage *progressBarImage = [UIImage imageNamed:@"progressBar.png"];
    [ProgressSlider setThumbImage:progressBarImage forState:UIControlStateNormal];
    [[UIApplication sharedApplication] beginReceivingRemoteControlEvents];
    

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
        
        [self.songs addObject:song];
    }
}

- (void)fileDownload:(NSIndexPath *)indexPath
{
    Song *song = [songs objectAtIndex:indexPath.row];
    
    NSURL *url = [NSURL URLWithString:song.s3Url];
    
    NSMutableURLRequest *request = [[NSMutableURLRequest alloc]initWithURL:url];
    
    //Create download operation and store metadata
    AFHTTPRequestOperation *operation = [[AFHTTPRequestOperation alloc]initWithRequest:request];
    operation.userInfo = [[NSMutableDictionary alloc]init];
    [operation.userInfo setValue:indexPath forKey:@"indexPath"];
    
    //Save file to resource folder
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSLibraryDirectory, NSUserDomainMask, YES);
    NSString *path = [paths objectAtIndex:0];
    NSString *fileName = [NSString stringWithFormat:@"/%d.mp3", (indexPath.row + 1)];
    NSString *filePath = [path stringByAppendingString:fileName];
    
    NSLog(@"%@", filePath);
    
    
    operation.outputStream = [NSOutputStream outputStreamToFileAtPath:filePath append:NO];
    
    NSLog(@"filePath = %@", filePath);
    
    [self addProgressIndicatortocell:indexPath];
    [self removeDownloadButtonfromcell:indexPath];

    //Download complete block
    [operation setCompletionBlockWithSuccess:^(AFHTTPRequestOperation *operation, id responseObject)
    {
        [timer invalidate];
        
        //Remove progress indicator
        [self removeProgressIndicatorfromcell:indexPath];
        
        //Add Duration Label
        UITableViewCell *cell = [tableView cellForRowAtIndexPath:indexPath];
        
        NSArray *paths = NSSearchPathForDirectoriesInDomains(NSLibraryDirectory, NSUserDomainMask, YES);
        NSString *path = [paths objectAtIndex:0];
        NSString *fileName = [NSString stringWithFormat:@"/%d.mp3", (indexPath.row + 1)];
        NSString *filePath = [path stringByAppendingString:fileName];
        
        NSError *err;
        
        AVAudioPlayer *tempPlayer = [[AVAudioPlayer alloc]initWithContentsOfURL:
                                     [[NSURL alloc]initFileURLWithPath:filePath] error:&err];
        
        if (err) {
            
            NSLog(@"AVAudioPlayer Init Error");
        
        }
        
        UILabel *lbl_duration = [[UILabel alloc]init];
        [lbl_duration setFrame:CGRectMake(240, 8, 70, 30)];
        lbl_duration.text = [self calculateDuration:tempPlayer.duration];
        lbl_duration.textAlignment = NSTextAlignmentRight;
        lbl_duration.backgroundColor = [UIColor clearColor];
        lbl_duration.font = [lbl_duration.font fontWithSize:10.0];
        [cell.contentView addSubview:lbl_duration];
        
        song.s3Url = @"(null)";
        song.duration = lbl_duration.text;
        
        NSString *plistPath = [bundleDocumentDirectoryPath stringByAppendingString:@"/PlayList.plist"];
        NSMutableDictionary *dictionary = [[NSMutableDictionary alloc] initWithContentsOfFile:plistPath];
        
        NSMutableDictionary *songArray = [dictionary objectForKey:song.songNumber];
        
        [songArray setObject:song.s3Url forKey:@"S3Url"];
        [songArray setObject:song.duration forKey:@"Duration"];
        //[songArray setObject:song.fileName forKey:@"FileName"];
        
        [dictionary writeToFile:plistPath atomically:NO];
        
        NSLog(@"Success");
    }
    //Failed
    failure:
     ^(AFHTTPRequestOperation *operation, NSError *error)
    {
        //Network Error, download failed
        UIAlertView *alert = [[UIAlertView alloc]initWithTitle:@"网络异常" message:@"下载失败" delegate:nil cancelButtonTitle:@"OK" otherButtonTitles: nil];
        
        //Todo add adtional download failed indicator as alertview is not friendly when multi download failed.
        [alert show];
        
        //Remove download indicator and add download Button Back
        [self removeProgressIndicatorfromcell:indexPath];
        [self addDownloadButtontocell:indexPath];
        
    }];

    //Progress block used to update progress
    [operation setDownloadProgressBlock:^(NSUInteger bytesRead, long long totalBytesRead, long long totalBytesExpectedToRead)
    {
        float progress = (float)(int)totalBytesRead/(float)(int)totalBytesExpectedToRead;
        
        //Weak operation as operation is still running and data is retained
        __weak AFHTTPRequestOperation *_operation = operation;
        NSIndexPath *indexPathforRow = [_operation.userInfo objectForKey:@"indexPath"];
        
        //Update progress
        UITableViewCell *cell = [tableView cellForRowAtIndexPath:indexPathforRow];
        for(UIView *oneView in cell.contentView.subviews)
        {
            if ([oneView isMemberOfClass:[DACircularProgressView class]])
            {
                DACircularProgressView * _progressIndicator = (DACircularProgressView *)oneView;
                _progressIndicator.progress = progress;
            }
        }
    }];
    
    //Add download request to download queue
    [httpClient enqueueHTTPRequestOperation:operation];
    
}

- (void)removeProgressIndicatorfromcell:(NSIndexPath *)indexPath
{
    UITableViewCell *cell = [tableView cellForRowAtIndexPath:indexPath];
    
    for (UIView *oneview in  cell.contentView.subviews)
    {
        //Remove Progress Indicator
        if ([oneview isMemberOfClass:[DACircularProgressView class]])
        {
            [oneview removeFromSuperview];
        }
        //Remove Pause download Button
        if ([oneview isKindOfClass:[UIButton class]]) {
            [oneview removeFromSuperview];
        }
    }
    
}

- (void)removeDownloadButtonfromcell:(NSIndexPath *)indexPath
{
    UITableViewCell *cell = [tableView cellForRowAtIndexPath:indexPath];
    
    //Remove download button
    for(UIView *oneView in cell.contentView.subviews)
    {
        if ([oneView isKindOfClass:[UIButton class]]) {
            if (oneView.tag == indexPath.row) {
            
                [oneView removeFromSuperview];
                break;
            }
            
        }
    }
}

- (void)addDownloadButtontocell:(NSIndexPath *)indexPath
{
    
    UITableViewCell *cell = [tableView cellForRowAtIndexPath:indexPath];
    
    UIButton *but = [UIButton buttonWithType:UIButtonTypeRoundedRect];
    [but setImage:[UIImage imageNamed:@"downloadButton.png"] forState:UIControlStateNormal];
    [but setFrame:CGRectMake(280, 8, 30, 30)];
    
    [but setTag:indexPath.row];
    [but addTarget:self action:@selector(onDownloadButtonClicked:) forControlEvents:UIControlEventTouchUpInside];
    
    [cell.contentView addSubview:but];
}

- (void)removeNowPlayingIndicator:(NSIndexPath *)indexPath
{
    UITableViewCell *cell = [tableView cellForRowAtIndexPath:indexPath];
    
    for (UIView *oneView in cell.contentView.subviews) {
        
        if ([oneView isMemberOfClass:[UIImageView class]]) {
            [oneView removeFromSuperview];
        }
    }
}

- (void)addProgressIndicatortocell:(NSIndexPath *)indexPath
{
    DACircularProgressView *progressIndicator = [[DACircularProgressView alloc]initWithFrame:CGRectMake(280.0f, 8.0f, 30.0f, 30.0f)];
    
    progressIndicator.roundedCorners = YES;
    progressIndicator.trackTintColor = [UIColor clearColor];
    progressIndicator.progressTintColor = [UIColor blueColor];
    
    UIButton *but = [UIButton buttonWithType:UIButtonTypeCustom];
    [but setImage:[UIImage imageNamed:@"downloadProgressButtonPause.png"] forState:UIControlStateNormal];
    [but setFrame:CGRectMake(282, 10, 26, 26)];
    
    //but.layer.cornerRadius = 12;
    
    UITableViewCell *cell = [tableView cellForRowAtIndexPath:indexPath];
    [cell.contentView addSubview:progressIndicator];
    [cell.contentView addSubview:but];
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
    SongCell *songCell = [self.tableView dequeueReusableCellWithIdentifier:@"SongCell"];
    
    songCell.selectionStyle = UITableViewCellSelectionStyleNone;
    
    Song *song = [self.songs objectAtIndex:indexPath.row];
        
    for (UIView *subView in songCell.contentView.subviews) {
        [subView removeFromSuperview];
    }
    
    //Title
    UILabel *lbl_title = [[UILabel alloc]init];
    [lbl_title setFrame:CGRectMake(30, 4, 150, 30)];
    lbl_title.text = song.title;
    lbl_title.backgroundColor = [UIColor clearColor];
    lbl_title.font = [lbl_title.font fontWithSize:18.0];
    [songCell.contentView addSubview:lbl_title];
    
    //Song had been downloaded
    if ([song.s3Url isEqualToString:@"(null)"]) {
        
        UILabel *lbl_duration = [[UILabel alloc]init];
        [lbl_duration setFrame:CGRectMake(240, 8, 70, 30)];
        lbl_duration.text = song.duration;
        lbl_duration.textAlignment = NSTextAlignmentRight;
        lbl_duration.backgroundColor = [UIColor clearColor];
        lbl_duration.font = [lbl_duration.font fontWithSize:10.0];
        [songCell.contentView addSubview:lbl_duration];
    }
    //Song is not avaliable
    else
    {
        
        //[self addDownloadButtontocell:indexPath];
        
        UIButton *but = [UIButton buttonWithType:UIButtonTypeRoundedRect];
        [but setBackgroundImage:[UIImage imageNamed:@"downloadButton.png"] forState:UIControlStateNormal];
        [but setFrame:CGRectMake(280, 8, 30, 30)];
        //[but setAlpha:0.8];
        
        //[but setTag:indexPath.row];
        [but addTarget:self action:@selector(onDownloadButtonClicked:) forControlEvents:UIControlEventTouchUpInside];
        
        [songCell.contentView addSubview:but];
    }
    
    return songCell;
}


-(void)onDownloadButtonClicked: (id)sender
{
    SongCell* cell =(SongCell*) [[[sender superview] superview]superview];
    currentDownloadIndexPath = [tableView indexPathForCell:cell];

    //Get Current Network Status
    NSString *currentNetWorkStatus = [self GetCurrntNetWorkStatus];
    
    //Network Error
    if (currentNetWorkStatus == nil) {
        UIAlertView *alert = [[UIAlertView alloc]initWithTitle:@"网络异常" message:@"当前网络无法连接" delegate:nil cancelButtonTitle:@"OK" otherButtonTitles: nil];
        
        [alert show];
        return;
        
    }
    //3G network connected
    if ([currentNetWorkStatus isEqual: @"3g"]) {
        
        UIAlertView *alert = [[UIAlertView alloc]initWithTitle:@"选择网络" message:@"是否使用3G网络下载资源，会产生流量" delegate:self cancelButtonTitle:@"取消" otherButtonTitles:@"使用", nil];
        
        [alert show];
    }
    
    //Wifi network connected
    
    if ([currentNetWorkStatus isEqual: @"wifi"]) {
        
        [self fileDownload:currentDownloadIndexPath];
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

- (void) pauseSong:(NSIndexPath *)indexPath
{
    [timer invalidate];
    [player pause];
    
    currentProgress = player.currentTime;
    
    UITableViewCell *cell = [self.tableView cellForRowAtIndexPath:currentPlayingIndexPath];
    for ( UIView *oneView in cell.contentView.subviews) {
        if ([oneView isMemberOfClass:[UIImageView class]])
        {
            [oneView removeFromSuperview];
        }
    }
    
    //Update UI adding nowplaying indicator, update progress slider
    UIImageView *cellImg = [[UIImageView alloc] initWithFrame:CGRectMake(8, 15, 13, 16)];
    cellImg.image = [UIImage imageNamed:@"NowPlayingPauseControl~iphone.png"];
    [cell.contentView addSubview:cellImg];
}


- (void) playOrResumeSong:(NSIndexPath *)indexPath
                       At:(NSTimeInterval)time
{
    [player stop];
    [timer invalidate];
    
    [self removeNowPlayingIndicator:currentPlayingIndexPath];
    
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
        
        //Store currently playing indexPath
        currentPlayingIndexPath = indexPath;
        
        UITableViewCell *cell = [self.tableView cellForRowAtIndexPath:currentPlayingIndexPath];
        for ( UIView *oneView in cell.contentView.subviews) {
            if ([oneView isMemberOfClass:[UIImageView class]])
            {
                [oneView removeFromSuperview];
            }
        }
        
        //Update UI adding nowplaying indicator, update progress slider
        UIImageView *cellImg = [[UIImageView alloc] initWithFrame:CGRectMake(8, 15, 13, 16)];
        cellImg.image = [UIImage imageNamed:@"nowPlayingGlyph.png"];
        [cell.contentView addSubview:cellImg];
        
        //Update Progress Slider
        self.currentProgress = time;
        self.timer = [NSTimer scheduledTimerWithTimeInterval:0.01
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
    [timer invalidate];

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

-(NSString*)GetCurrntNetWorkStatus
{
    NSString* result;
    Reachability *r = [Reachability reachabilityWithHostname:@"www.apple.com"];
    
    switch ([r currentReachabilityStatus]) {
        case NotReachable:
            result=nil;
            break;
        case ReachableViaWWAN:// 使用3G网络
            result=@"3g";
            break;
        case ReachableViaWiFi:// 使用WiFi网络
            result=@"wifi";
            break;
    }
    return result;
}

@end
