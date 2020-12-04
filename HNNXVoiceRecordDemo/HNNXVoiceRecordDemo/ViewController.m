//
//  ViewController.m
//  HNNXVoiceRecordDemo
//
//  Created by Whisper on 2020/12/3.
//

#import "ViewController.h"
#import <WebKit/WebKit.h>
#import <AVFoundation/AVFoundation.h>
#import <AudioToolbox/AudioToolbox.h>
#import "LameTool.h"

#define recordHomePath [NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES) lastObject]

@interface ViewController ()<WKUIDelegate,WKNavigationDelegate,AVAudioPlayerDelegate,AVAudioRecorderDelegate>
{
    WKWebView *WebView;
    AVAudioRecorder *audioRecorder;
    AVAudioSession *audioSession;
    NSString *currentAudioType;
    NSString *currentAudioPath;
    AVAudioPlayer *_avAudioPlayer;
}
@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view.
    self.view.backgroundColor = [UIColor whiteColor];
    currentAudioType = @"mp3";
    WebView = [[WKWebView alloc] initWithFrame:self.view.bounds];
    [WebView.configuration.preferences setValue:@YES forKey:@"allowFileAccessFromFileURLs"];
    [WebView loadRequest:[NSURLRequest requestWithURL:[NSURL fileURLWithPath:[[NSBundle mainBundle] pathForResource:@"testDemo" ofType:@"html"]]]];
    WebView.UIDelegate = self;
    WebView.navigationDelegate = self;
    [self.view addSubview:WebView];
}

- (void)viewWillAppear:(BOOL)animated{
    [super viewWillAppear:animated];
    [self.navigationController setNavigationBarHidden:YES animated:YES];
}


//WKUIDelegate
- (void)webView:(WKWebView *)webView runJavaScriptAlertPanelWithMessage:(NSString *)message initiatedByFrame:(WKFrameInfo *)frame completionHandler:(void (^)(void))completionHandler
{
    // 提供alert的功能
    UIAlertController *alertController = [UIAlertController alertControllerWithTitle:message
                                                                             message:nil
                                                                      preferredStyle:UIAlertControllerStyleAlert];
    [alertController addAction:[UIAlertAction actionWithTitle:@"OK"
                                                        style:UIAlertActionStyleCancel
                                                      handler:^(UIAlertAction *action) {
        completionHandler();
    }]];
    [self presentViewController:alertController animated:YES completion:nil];
    
}

- (void)webView:(WKWebView *)webView decidePolicyForNavigationAction:(WKNavigationAction *)navigationAction decisionHandler:(void (^)(WKNavigationActionPolicy))decisionHandler{
    NSString *urlString = navigationAction.request.URL.absoluteString;
    if([urlString containsString:@"wc://"]){
        if(![urlString containsString:@"wc://jsbridge"]){
            [self decidePolicyCallBackWithCode:@"102" message:@"协议找不到（找不到JSBridge）" result:@{}];
            return;
        }
        NSString *method = [[[[urlString componentsSeparatedByString:@"?"] firstObject] componentsSeparatedByString:@"/"] lastObject];
        NSString *query = [[[[[[[[urlString componentsSeparatedByString:@"?"] lastObject] stringByReplacingOccurrencesOfString:@"{" withString:@""] stringByReplacingOccurrencesOfString:@"" withString:@"}"] stringByReplacingOccurrencesOfString:@"%22" withString:@""] stringByReplacingOccurrencesOfString:@"%7B" withString:@""] stringByReplacingOccurrencesOfString:@"%7D" withString:@""] stringByReplacingOccurrencesOfString:@" " withString:@""];
        
        NSArray *querItems = [query componentsSeparatedByString:@","];
        if(querItems.count == 0){
            [self decidePolicyCallBackWithCode:@"101" message:@"消息不合法（前端传递过来的消息为空或格式不对）" result:@{}];
            return;
        }
        NSMutableDictionary *querItemsDic = [NSMutableDictionary dictionary];
        for (NSString *str in querItems) {
            NSArray *array = [str componentsSeparatedByString:@":"];
            if(array.count == 2){
                [querItemsDic setObject:array.lastObject forKey:array.firstObject];
            }
        }
        NSString *nameStr = [NSString stringWithFormat:@"voiceRecod.caf"];
        NSString *path = [recordHomePath stringByAppendingPathComponent:nameStr];
        if([method isEqualToString:@"startRecord"]){
            currentAudioType = querItemsDic[@"mediaType"]?:@"mp3";
            NSURL *url = [NSURL URLWithString:path];
            // setting:录音的设置项
            NSDictionary *recordSettings = @{// 编码格式
                AVFormatIDKey:@(kAudioFormatLinearPCM),
                // 采样率
                AVSampleRateKey:querItemsDic[@"sampleRate"]?[NSNumber numberWithFloat:[querItemsDic[@"sampleRate"] floatValue]]:@(44000.0),
                // 通道数
                AVNumberOfChannelsKey:@(2),
                //采样位数
                AVLinearPCMBitDepthKey:querItemsDic[@"bitRate"]?[NSNumber numberWithInt:[querItemsDic[@"bitRate"] intValue]]:@(128),
                // 录音质量
                AVEncoderAudioQualityKey:@(AVAudioQualityHigh)
            };
            audioRecorder = [[AVAudioRecorder alloc] initWithURL:url settings:recordSettings error:nil];
            audioRecorder.delegate = self;
            //开启音量检测
            audioRecorder.meteringEnabled = YES;
            audioSession = [AVAudioSession sharedInstance];//得到AVAudioSession单例对象
            if (![audioRecorder isRecording]) {
                [audioSession setCategory:AVAudioSessionCategoryPlayAndRecord error:nil];//设置类别,表示该应用同时支持播放和录音
                [audioSession setActive:YES error:nil];//启动音频会话管理,此时会阻断后台音乐的播放.
                
                [audioRecorder prepareToRecord];
                [audioRecorder peakPowerForChannel:0.0];
                [audioRecorder recordForDuration:60];
            }
        }else if ([method isEqualToString:@"stopRecord"]){
            [audioRecorder stop];
            [audioSession setActive:NO error:nil];
        }else if ([method isEqualToString:@"playRecord"]){
            if(!currentAudioPath){
                decisionHandler(WKNavigationActionPolicyCancel);
                return;
            }
            NSURL *fileUrl=[NSURL fileURLWithPath:currentAudioPath];
            [audioSession setCategory:AVAudioSessionCategoryPlayback error:nil];//设置类别,表示该应用同时支持播放和录音
            [audioSession setActive:YES error:nil];//启动音频会话管理,此时会阻断后台音乐的播放.
            NSError *error;
            // (3)初始化音频类 并且添加播放文件
            _avAudioPlayer = [[AVAudioPlayer alloc] initWithContentsOfURL:fileUrl error:&error];
            // (4) 设置代理
            _avAudioPlayer.delegate = self;
            // (5) 设置初始音量大小 默认1，取值范围 0~1
            _avAudioPlayer.volume = 1;
            // (6)设置音乐播放次数 负数为一直循环，直到stop，0为一次，1为2次，以此类推
            _avAudioPlayer.numberOfLoops = 0;
            // (5)准备播放
            [_avAudioPlayer prepareToPlay];
            [_avAudioPlayer play];
        }else{
            [self decidePolicyCallBackWithCode:@"103" message:@"action找不到（找不到要调用的方法）" result:@{}];
        }
        decisionHandler(WKNavigationActionPolicyCancel);
    }else{
        decisionHandler(WKNavigationActionPolicyAllow);
    }
}

- (void)decidePolicyCallBackWithCode:(NSString *)code message:(NSString *)message result:(NSDictionary *)result{
    NSDictionary *dic = @{@"error_code":code,@"error_msg":message,@"result":result};
    NSString *jsonString = @"";
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:dic options:0 error:nil];
    if(jsonData){
        jsonString = [[NSString alloc]initWithData:jsonData encoding:NSUTF8StringEncoding];
    }
    [WebView evaluateJavaScript:[NSString stringWithFormat:@"this.recordOnComplete('%@')",jsonString] completionHandler:^(id _Nullable result, NSError * _Nullable error) {
        
    }];
}

- (void)finishRecord{
    NSString *nameStr = [NSString stringWithFormat:@"voiceRecod.caf"];
    NSString *path = [recordHomePath stringByAppendingPathComponent:nameStr];
    NSString *outPath;
    if([currentAudioType isEqualToString:@"mp3"]){
        outPath = [LameTool audioToMP3:path isDeleteSourchFile:YES];
    }else if([currentAudioType isEqualToString:@"wav"]){
        outPath = [self convertToWav:path isDeleteSourchFile:YES];
    }else if([currentAudioType isEqualToString:@"amr"]){
    }
    NSData *mp3Data = [NSData dataWithContentsOfFile:outPath];
    NSString *encodedImageStr = [mp3Data base64EncodedStringWithOptions:0];
    [self decidePolicyCallBackWithCode:@"0" message:@"成功" result:@{@"mp3Base64":encodedImageStr}];
    currentAudioPath = outPath;
    NSLog(@"---->%@",outPath);
}

- (void)audioRecorderDidFinishRecording:(AVAudioRecorder *)recorder successfully:(BOOL)flag{
    if(flag){
        [self finishRecord];
    }else{
        [self decidePolicyCallBackWithCode:@"104" message:@"方法调用失败" result:@{}];
    }
}

- (void)audioPlayerDidFinishPlaying:(AVAudioPlayer *)player successfully:(BOOL)flag{
    [audioSession setCategory:AVAudioSessionCategoryPlayAndRecord error:nil];//设置类别,表示该应用同时支持播放和录音
    [audioSession setActive:YES error:nil];//启动音频会话管理,此时会阻断后台音乐的播放.
}

- (void)audioPlayerDecodeErrorDidOccur:(AVAudioPlayer *)player error:(NSError *)error{
    [audioSession setCategory:AVAudioSessionCategoryPlayAndRecord error:nil];//设置类别,表示该应用同时支持播放和录音
    [audioSession setActive:YES error:nil];//启动音频会话管理,此时会阻断后台音乐的播放.
}

- (NSString *) convertToWav:(NSString *)sourcePath isDeleteSourchFile: (BOOL)isDelete;
{
    // set up an AVAssetReader to read from the iPod Library
    
    NSURL *assetURL = [NSURL fileURLWithPath:sourcePath];
    AVURLAsset *songAsset = [AVURLAsset URLAssetWithURL:assetURL options:nil];
    
    NSError *assetError = nil;
    AVAssetReader *assetReader = [AVAssetReader assetReaderWithAsset:songAsset
                                                               error:&assetError]
    ;
    if (assetError) {
        NSLog (@"error: %@", assetError);
        return @"";
    }
    
    AVAssetReaderOutput *assetReaderOutput = [AVAssetReaderAudioMixOutput
                                              assetReaderAudioMixOutputWithAudioTracks:songAsset.tracks
                                              audioSettings: nil];
    if (! [assetReader canAddOutput: assetReaderOutput]) {
        NSLog (@"can't add reader output... die!");
        return @"";
    }
    [assetReader addOutput: assetReaderOutput];
    
    NSString *wavFilePath = [[sourcePath stringByDeletingPathExtension] stringByAppendingString:@".wav"];
    
    if ([[NSFileManager defaultManager] fileExistsAtPath:wavFilePath])
        {
        [[NSFileManager defaultManager] removeItemAtPath:wavFilePath error:nil];
        }
    NSURL *exportURL = [NSURL fileURLWithPath:wavFilePath];
    AVAssetWriter *assetWriter = [AVAssetWriter assetWriterWithURL:exportURL
                                                          fileType:AVFileTypeWAVE
                                                             error:&assetError];
    if (assetError)
        {
        NSLog (@"error: %@", assetError);
        return @"";
        }
    
    AudioChannelLayout channelLayout;
    memset(&channelLayout, 0, sizeof(AudioChannelLayout));
    channelLayout.mChannelLayoutTag = kAudioChannelLayoutTag_Stereo;
    NSDictionary *outputSettings = [NSDictionary dictionaryWithObjectsAndKeys:
                                    [NSNumber numberWithInt:kAudioFormatLinearPCM], AVFormatIDKey,
                                    [NSNumber numberWithFloat:44100.0], AVSampleRateKey,
                                    [NSNumber numberWithInt:2], AVNumberOfChannelsKey,
                                    [NSData dataWithBytes:&channelLayout length:sizeof(AudioChannelLayout)], AVChannelLayoutKey,
                                    [NSNumber numberWithInt:16], AVLinearPCMBitDepthKey,
                                    [NSNumber numberWithBool:NO], AVLinearPCMIsNonInterleaved,
                                    [NSNumber numberWithBool:NO],AVLinearPCMIsFloatKey,
                                    [NSNumber numberWithBool:NO], AVLinearPCMIsBigEndianKey,
                                    nil];
    AVAssetWriterInput *assetWriterInput = [AVAssetWriterInput assetWriterInputWithMediaType:AVMediaTypeAudio
                                                                              outputSettings:outputSettings];
    if ([assetWriter canAddInput:assetWriterInput])
        {
        [assetWriter addInput:assetWriterInput];
        }
    else
        {
        NSLog (@"can't add asset writer input... die!");
        return @"";
        }
    
    assetWriterInput.expectsMediaDataInRealTime = NO;
    
    [assetWriter startWriting];
    [assetReader startReading];
    
    AVAssetTrack *soundTrack = [songAsset.tracks objectAtIndex:0];
    CMTime startTime = CMTimeMake (0, soundTrack.naturalTimeScale);
    [assetWriter startSessionAtSourceTime: startTime];
    
    __block UInt64 convertedByteCount = 0;
    dispatch_queue_t mediaInputQueue = dispatch_queue_create("mediaInputQueue", NULL);
    
    [assetWriterInput requestMediaDataWhenReadyOnQueue:mediaInputQueue
                                            usingBlock: ^
     {
    
    while (assetWriterInput.readyForMoreMediaData)
        {
        CMSampleBufferRef nextBuffer = [assetReaderOutput copyNextSampleBuffer];
        if (nextBuffer)
            {
            // append buffer
            [assetWriterInput appendSampleBuffer: nextBuffer];
            convertedByteCount += CMSampleBufferGetTotalSampleSize (nextBuffer);
            CMTime progressTime = CMSampleBufferGetPresentationTimeStamp(nextBuffer);
            
            CMTime sampleDuration = CMSampleBufferGetDuration(nextBuffer);
            if (CMTIME_IS_NUMERIC(sampleDuration))
                progressTime= CMTimeAdd(progressTime, sampleDuration);
            float dProgress= CMTimeGetSeconds(progressTime) / CMTimeGetSeconds(songAsset.duration);
            NSLog(@"%f",dProgress);
            }
        else
            {
            
            [assetWriterInput markAsFinished];
            //              [assetWriter finishWriting];
            [assetReader cancelReading];
            
            }
        }
    }];
    if (isDelete) {
        NSError *error;
        [[NSFileManager defaultManager] removeItemAtPath:sourcePath error:&error];
        if (error == nil) {
            NSLog(@"删除源文件成功");
        }
    }
    return wavFilePath;
}

@end
