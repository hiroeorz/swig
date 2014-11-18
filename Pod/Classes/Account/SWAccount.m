//
//  SWAccount.m
//  swig
//
//  Created by Pierre-Marc Airoldi on 2014-08-21.
//  Copyright (c) 2014 PeteAppDesigns. All rights reserved.
//

#import "SWAccount.h"
#import "SWAccountConfiguration.h"
#import "SWEndpoint.h"
#import "SWCall.h"
#import "SWUriFormatter.h"
#import "NSString+PJString.h"

#import "pjsua.h"

#define kRegTimeout 800

@interface SWAccount ()

@property (nonatomic, strong) SWAccountConfiguration *configuration;
@property (nonatomic, strong) NSMutableArray *calls;

@end

@implementation SWAccount

-(instancetype)init {
    
    self = [super init];
    
    if (!self) {
        return nil;
    }
    
    _calls = [NSMutableArray new];
    
    return self;
}

-(void)dealloc {
    
}

-(void)setAccountId:(NSInteger)accountId {
    
    _accountId = accountId;
}

-(void)setAccountState:(SWAccountState)accountState {
    
    [self willChangeValueForKey:@"accountState"];
    _accountState = accountState;
    [self didChangeValueForKey:@"accountState"];
}

-(void)setAccountConfiguration:(SWAccountConfiguration *)accountConfiguration {
    
    [self willChangeValueForKey:@"accountConfiguration"];
    _accountConfiguration = accountConfiguration;
    [self didChangeValueForKey:@"accountConfiguration"];
}

-(void)configure:(SWAccountConfiguration *)configuration completionHandler:(void(^)(NSError *error))handler {
    
    self.accountConfiguration = configuration;
    
    if (!self.accountConfiguration.address) {
        self.accountConfiguration.address = [SWAccountConfiguration addressFromUsername:self.accountConfiguration.username domain:self.accountConfiguration.domain];
    }
    
    NSString *tcpSuffix = @"";
    
    if ([[SWEndpoint sharedEndpoint] hasTCPConfiguration]) {
        tcpSuffix = @";transport=TCP";
    }
    
    pjsua_acc_config acc_cfg;
    pjsua_acc_config_default(&acc_cfg);
    
    acc_cfg.id = [[SWUriFormatter sipUri:[self.accountConfiguration.address stringByAppendingString:tcpSuffix] withDisplayName:self.accountConfiguration.displayName] pjString];
    acc_cfg.reg_uri = [[SWUriFormatter sipUri:[self.accountConfiguration.domain stringByAppendingString:tcpSuffix]] pjString];
    acc_cfg.register_on_acc_add = self.accountConfiguration.registerOnAdd ? PJ_TRUE : PJ_FALSE;;
    acc_cfg.publish_enabled = self.accountConfiguration.publishEnabled ? PJ_TRUE : PJ_FALSE;
    acc_cfg.reg_timeout = kRegTimeout;
    
    acc_cfg.cred_count = 1;
    acc_cfg.cred_info[0].scheme = [self.accountConfiguration.authScheme pjString];
    acc_cfg.cred_info[0].realm = [self.accountConfiguration.authRealm pjString];
    acc_cfg.cred_info[0].username = [self.accountConfiguration.username pjString];
    acc_cfg.cred_info[0].data_type = PJSIP_CRED_DATA_PLAIN_PASSWD;
    acc_cfg.cred_info[0].data = [self.accountConfiguration.password pjString];

    /* Enable incomming video auto show.
     
     // from log
     . dev_id 0: iPhone IO device  (in=1, out=1) 8000Hz
     ..core audio initialized
     ..select() I/O Queue created
     ..Initializing video subsystem..

     ...OpenH264 codec  initialized
     ...OpenGL   device initialized
     ...iOS      video  initialized with 3 devices:

     ... 0: [Renderer] iOS - UIView
     ... 1: [Capturer] iOS - Front Camera
     ... 2: [Capturer] iOS - Back Camera

     ...Colorbar video src initialized with 1 device(s):
     ... 0: Colorbar generator
     */

    /* device No
       0: Render device
       2: Front Camera
       3: Back Camera
     */
    acc_cfg.vid_in_auto_show = PJ_TRUE;
    acc_cfg.vid_out_auto_transmit = PJ_TRUE;
    acc_cfg.vid_cap_dev = 3;
    acc_cfg.vid_rend_dev = 0;

    if (!self.accountConfiguration.proxy) {
        acc_cfg.proxy_cnt = 0;
    }
    
    else {
        acc_cfg.proxy_cnt = 1;
        acc_cfg.proxy[0] = [[SWUriFormatter sipUri:[self.accountConfiguration.proxy stringByAppendingString:tcpSuffix]] pjString];
    }
    
    pj_status_t status;
    
    int accountId = (int)self.accountId;
    
    status = pjsua_acc_add(&acc_cfg, PJ_TRUE, &accountId);
    
    if (status != PJ_SUCCESS) {
        
        NSError *error = [NSError errorWithDomain:@"Error adding account" code:status userInfo:nil];
        
        if (handler) {
            handler(error);
        }
        
        return;
    }
    
    else {
        [[SWEndpoint sharedEndpoint] addAccount:self];
    }
    
    if (!self.accountConfiguration.registerOnAdd) {
        [self connect:handler];
    }
    
    else {
        
        if (handler) {
            handler(nil);
        }
    }
}

+ (void)setResolutionWidth:(NSInteger)width Height:(NSInteger)height {
    const pj_str_t codec_id = {"H264", 4};
    pjmedia_vid_codec_param param;
    pjsua_vid_codec_get_param(&codec_id, &param);
    param.enc_fmt.det.vid.size.w = (int)width;
    param.enc_fmt.det.vid.size.h = (int)height;
    param.dec_fmt.det.vid.size.w = (int)width;
    param.dec_fmt.det.vid.size.h = (int)height;
    pjsua_vid_codec_set_param(&codec_id, &param);
}

+ (UIView *)getVideoView:(NSInteger)windowIndex {
    pjsua_vid_win_info info;
    pjsua_vid_win_get_info(windowIndex, &info);
    pjmedia_vid_dev_hwnd hwnd = info.hwnd;
    UIView *view = (__bridge UIView *)hwnd.info.ios.window;
    view.hidden = NO;
    return view;
}

+ (void)addTransmissionVideo:(NSInteger)callId {
    pjsua_call_set_vid_strm(callId, PJSUA_CALL_VID_STRM_ADD, NULL);
}

+ (void)removeTransmissionVideo:(NSInteger)callId {
    pjsua_call_set_vid_strm(callId, PJSUA_CALL_VID_STRM_REMOVE, NULL);
}

+ (void)startTransmissionVideo:(NSInteger)callId {
    pjsua_call_set_vid_strm(callId, PJSUA_CALL_VID_STRM_START_TRANSMIT, NULL);
}

+ (void)stopTransmissionVideo:(NSInteger)callId {
    pjsua_call_set_vid_strm(callId, PJSUA_CALL_VID_STRM_STOP_TRANSMIT, NULL);
}

+ (void)setH264Profile {
    const pj_str_t codec_id = {"H264", 4};
    pjmedia_vid_codec_param param;
    pjsua_vid_codec_get_param(&codec_id, &param);

    param.dec_fmtp.param[0].name = pj_str("profile-level-id");
    /* Set the profile level to "1f", which means level 3.1 */
    /* Set the profile level to "1e", which means level 3.0 */
    /* Set the profile level to "15", which means level 2.1 */
    param.dec_fmtp.param[0].val = pj_str("xxxx1f");
    pjsua_vid_codec_set_param(&codec_id, &param);
}

+ (void)changeOrientationWindowId:(NSInteger)windowId angle:(NSInteger)angle {
    pjsua_vid_win_rotate((int)windowId, (int)angle);
}

-(void)connect:(void(^)(NSError *error))handler {
    
    //FIX: registering too often will cause the server to possibly return error
        
    pj_status_t status;
    
    status = pjsua_acc_set_registration((int)self.accountId, PJ_TRUE);
    
    if (status != PJ_SUCCESS) {
        
        NSError *error = [NSError errorWithDomain:@"Error setting registration" code:status userInfo:nil];
        
        if (handler) {
            handler(error);
        }
        
        return;
    }
    
    status = pjsua_acc_set_online_status((int)self.accountId, PJ_TRUE);
    
    if (status != PJ_SUCCESS) {
        
        NSError *error = [NSError errorWithDomain:@"Error setting online status" code:status userInfo:nil];
        
        if (handler) {
            handler(error);
        }
        
        return;
    }
    
    if (handler) {
        handler(nil);
    }
}

-(void)disconnect:(void(^)(NSError *error))handler {
    
    pj_status_t status;
    
    status = pjsua_acc_set_online_status((int)self.accountId, PJ_FALSE);
    
    if (status != PJ_SUCCESS) {
        
        NSError *error = [NSError errorWithDomain:@"Error setting online status" code:status userInfo:nil];
        
        if (handler) {
            handler(error);
        }
        
        return;
    }
    
    status = pjsua_acc_set_registration((int)self.accountId, PJ_FALSE);
    
    if (status != PJ_SUCCESS) {
        
        NSError *error = [NSError errorWithDomain:@"Error setting registration" code:status userInfo:nil];
        
        if (handler) {
            handler(error);
        }
        
        return;
    }
    
    if (handler) {
        handler(nil);
    }
}

-(void)accountStateChanged {
    
    pjsua_acc_info accountInfo;
    pjsua_acc_get_info((int)self.accountId, &accountInfo);
    
    pjsip_status_code code = accountInfo.status;
    
    //TODO make status offline/online instead of offline/connect
    //status would be disconnected, online, and offline, isConnected could return true if online/offline
    
    if (code == 0 || accountInfo.expires == -1) {
        self.accountState = SWAccountStateDisconnected;
    }
    
    else if (PJSIP_IS_STATUS_IN_CLASS(code, 100) || PJSIP_IS_STATUS_IN_CLASS(code, 300)) {
        self.accountState = SWAccountStateConnecting;
    }
    
    else if (PJSIP_IS_STATUS_IN_CLASS(code, 200)) {
        self.accountState = SWAccountStateConnected;
    }
    
    else {
        self.accountState = SWAccountStateDisconnected;
    }
}

-(BOOL)isValid {
    
    return pjsua_acc_is_valid((int)self.accountId);
}

#pragma Call Management

-(void)addCall:(SWCall *)call {
    
    [self.calls addObject:call];
    
    //TODO:: setup blocks
}

-(void)removeCall:(NSUInteger)callId {
    
    SWCall *call = [self lookupCall:callId];
    
    if (call) {
        [self.calls removeObject:call];
    }
    
    call = nil;
}

-(SWCall *)lookupCall:(NSInteger)callId {
    
    NSUInteger callIndex = [self.calls indexOfObjectPassingTest:^BOOL(id obj, NSUInteger idx, BOOL *stop) {
        
        SWCall *call = (SWCall *)obj;
        
        if (call.callId == callId && call.callId != PJSUA_INVALID_ID) {
            return YES;
        }
        
        return NO;
    }];
    
    if (callIndex != NSNotFound) {
        return [self.calls objectAtIndex:callIndex]; //TODO add more management
    }
    
    else {
        return nil;
    }
}

-(SWCall *)firstCall {
    
    if (self.calls.count > 0) {
        return self.calls[0];
    }
    
    else {
        return nil;
    }
}

-(void)endAllCalls {
    
    for (SWCall *call in self.calls) {
        [call hangup:nil];
    }
}

-(void)makeCall:(NSString *)URI completionHandler:(void(^)(NSError *error))handler {
    
    pj_status_t status;
    NSError *error;
    
    pjsua_call_id callIdentifier;
    pj_str_t uri = [[SWUriFormatter sipUri:URI fromAccount:self] pjString];
    
    status = pjsua_call_make_call((int)self.accountId, &uri, 0, NULL, NULL, &callIdentifier);
    
    if (status != PJ_SUCCESS) {
        
        error = [NSError errorWithDomain:@"Error hanging up call" code:0 userInfo:nil];
    }
    
    else {
        
        SWCall *call = [SWCall callWithId:callIdentifier accountId:self.accountId inBound:NO];
        
        [self addCall:call];
    }
    
    if (handler) {
        handler(error);
    }
}

@end