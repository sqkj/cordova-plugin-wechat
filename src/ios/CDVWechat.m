//
//  CDVWechat.m
//  cordova-plugin-wechat
//
//  Created by xu.li on 12/23/13.
//
//

#import "CDVWechat.h"

@implementation CDVWechat

#pragma mark "API"

- (void)share:(CDVInvokedUrlCommand *)command
{
    // if not installed
    if (![WXApi isWXAppInstalled])
    {
        [self failWithCallbackID:command.callbackId withMessage:@"未安装微信"];
        return ;
    }

    // check arguments
    NSDictionary *params = [command.arguments objectAtIndex:0];
    if (!params)
    {
        [self failWithCallbackID:command.callbackId withMessage:@"参数格式错误"];
        return ;
    }
    
    // save the callback id
    self.currentCallbackId = command.callbackId;
    
    SendMessageToWXReq* req = [[SendMessageToWXReq alloc] init];
    
    // check the scene
    if ([params objectForKey:@"scene"])
    {
        req.scene = [[params objectForKey:@"scene"] integerValue];
    }
    else
    {
        req.scene = WXSceneTimeline;
    }
    
    // message or text?
    NSDictionary *message = [params objectForKey:@"message"];
    
    if (message)
    {
        req.bText = NO;

        // async
        [self.commandDelegate runInBackground:^{
            req.message = [self buildSharingMessage:message];
            if (![WXApi sendReq:req])
            {
                [self failWithCallbackID:command.callbackId withMessage:@"参数错误"];
                self.currentCallbackId = nil;
            }
        }];
    }
    else
    {
        req.bText = YES;
        req.text = [params objectForKey:@"text"];
        
        if (![WXApi sendReq:req])
        {
            [self failWithCallbackID:command.callbackId withMessage:@"参数错误"];
            self.currentCallbackId = nil;
        }
    }
}

- (void)registerApp:(NSString *)wechatAppId
{
    self.wechatAppId = wechatAppId;
    
    [WXApi registerApp:wechatAppId];

    NSLog(@"Register wechat app: %@", wechatAppId);
}

#pragma mark "WXApiDelegate"

/**
 * Not implemented
 */
- (void)onReq:(BaseReq *)req
{
    NSLog(@"%@", req);
}

- (void)onResp:(BaseResp *)resp
{
    BOOL success = NO;
    NSString *message = @"Unknown";
    
    if([resp isKindOfClass:[SendMessageToWXResp class]])
    {
        switch (resp.errCode)
        {
            case WXSuccess:
                success = YES;
            break;
            
            case WXErrCodeCommon:
                message = @"普通错误类型";
            break;
            
            case WXErrCodeUserCancel:
                message = @"用户点击取消并返回";
            break;
            
            case WXErrCodeSentFail:
                message = @"发送失败";
            break;
            
            case WXErrCodeAuthDeny:
                message = @"授权失败";
            break;
            
            case WXErrCodeUnsupport:
                message = @"微信不支持";
            break;
        }
    }
    
    
    if (success)
    {
        [self successWithCallbackID:self.currentCallbackId];
    }
    else
    {
        [self failWithCallbackID:self.currentCallbackId withMessage:message];
    }
    
    self.currentCallbackId = nil;
}

#pragma mark "CDVPlugin Overrides"

- (void)handleOpenURL:(NSNotification *)notification
{
    NSURL* url = [notification object];
    
    if ([url isKindOfClass:[NSURL class]] && [url.scheme isEqualToString:self.wechatAppId])
    {
        [WXApi handleOpenURL:url delegate:self];
    }
}

#pragma mark "Private methods"

- (WXMediaMessage *)buildSharingMessage:(NSDictionary *)message
{
    WXMediaMessage *wxMediaMessage = [WXMediaMessage message];
    wxMediaMessage.title = [message objectForKey:@"title"];
    wxMediaMessage.description = [message objectForKey:@"description"];
    wxMediaMessage.mediaTagName = [message objectForKey:@"mediaTagName"];
    wxMediaMessage.messageExt = [message objectForKey:@"messageExt"];
    wxMediaMessage.messageAction = [message objectForKey:@"messageAction"];
    if ([message objectForKey:@"thumb"])
    {
        [wxMediaMessage setThumbImage:[self getUIImageFromURL:[message objectForKey:@"thumb"]]];
    }
    
    // media parameters
    id mediaObject = nil;
    NSDictionary *media = [message objectForKey:@"media"];
    
    // check types
    NSInteger type = [[media objectForKey:@"type"] integerValue];
    switch (type)
    {
        case CDVWXSharingTypeApp:
            mediaObject = [WXAppExtendObject object];
            ((WXAppExtendObject*)mediaObject).extInfo = [media objectForKey:@"extInfo"];
            ((WXAppExtendObject*)mediaObject).url = [media objectForKey:@"url"];
        break;
    
        case CDVWXSharingTypeEmotion:
            mediaObject = [WXEmoticonObject object];
            ((WXEmoticonObject*)mediaObject).emoticonData = [self getNSDataFromURL:[media objectForKey:@"emotion"]];
        break;
        
        case CDVWXSharingTypeFile:
            mediaObject = [WXFileObject object];
            ((WXFileObject*)mediaObject).fileData = [self getNSDataFromURL:[media objectForKey:@"file"]];
        break;
        
        case CDVWXSharingTypeImage:
            mediaObject = [WXImageObject object];
            ((WXImageObject*)mediaObject).imageData = [self getNSDataFromURL:[media objectForKey:@"image"]];
        break;
        
        case CDVWXSharingTypeMusic:
            mediaObject = [WXMusicObject object];
            ((WXMusicObject*)mediaObject).musicUrl = [media objectForKey:@"musicUrl"];
            ((WXMusicObject*)mediaObject).musicDataUrl = [media objectForKey:@"musicDataUrl"];
        break;
        
        case CDVWXSharingTypeVideo:
            mediaObject = [WXVideoObject object];
            ((WXVideoObject*)mediaObject).videoUrl = [media objectForKey:@"videoUrl"];
        break;
        
        case CDVWXSharingTypeWebPage:
        default:
        mediaObject = [WXWebpageObject object];
        ((WXWebpageObject *)mediaObject).webpageUrl = [media objectForKey:@"webpageUrl"];
    }

    wxMediaMessage.mediaObject = mediaObject;
    return wxMediaMessage;
}

- (NSData *)getNSDataFromURL:(NSString *)url
{
    NSData *data = nil;

    if ([url hasPrefix:@"http://"] || [url hasPrefix:@"https://"])
    {
        data = [NSData dataWithContentsOfURL:[NSURL URLWithString:url]];
    }
    else
    {
        // local file
        url = [[NSBundle mainBundle] pathForResource:[url stringByDeletingPathExtension] ofType:[url pathExtension]];
        data = [NSData dataWithContentsOfFile:url];
    }
    
    return data;
}

- (UIImage *)getUIImageFromURL:(NSString *)url
{
    NSData *data = [self getNSDataFromURL:url];
    return [UIImage imageWithData:data];
}

- (void)successWithCallbackID:(NSString *)callbackID
{
    [self successWithCallbackID:callbackID withMessage:@"OK"];
}

- (void)successWithCallbackID:(NSString *)callbackID withMessage:(NSString *)message
{
    CDVPluginResult *commandResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsString:message];
    [self.commandDelegate sendPluginResult:commandResult callbackId:callbackID];
}

- (void)failWithCallbackID:(NSString *)callbackID withError:(NSError *)error
{
    [self failWithCallbackID:callbackID withMessage:[error localizedDescription]];
}

- (void)failWithCallbackID:(NSString *)callbackID withMessage:(NSString *)message
{
    CDVPluginResult *commandResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:message];
    [self.commandDelegate sendPluginResult:commandResult callbackId:callbackID];
}

@end