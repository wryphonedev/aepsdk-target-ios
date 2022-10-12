/*
 Copyright 2021 Adobe. All rights reserved.
 This file is licensed to you under the Apache License, Version 2.0 (the "License");
 you may not use this file except in compliance with the License. You may obtain a copy
 of the License at http://www.apache.org/licenses/LICENSE-2.0
 Unless required by applicable law or agreed to in writing, software distributed under
 the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR REPRESENTATIONS
 OF ANY KIND, either express or implied. See the License for the specific language
 governing permissions and limitations under the License.
 */

#import "ViewController.h"

@interface ViewController ()
@property (weak, nonatomic) IBOutlet UILabel *lblSessionId;
@property (weak, nonatomic) IBOutlet UILabel *lblThirdParty;
@property (weak, nonatomic) IBOutlet UILabel *lblTntId;
@property (weak, nonatomic) IBOutlet UITextField *textSessionID;
@property (weak, nonatomic) IBOutlet UITextField *textThirdPartyID;
@property (weak, nonatomic) IBOutlet UITextField *textTntID;
@property (weak, nonatomic) IBOutlet UITextField *griffonUrl;

@property NSMutableArray* notificationTokens;

@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view.
    self.notificationTokens = [[NSMutableArray alloc] init];
}


- (IBAction)prefetchClicked:(id)sender {
    AEPTargetPrefetchObject *prefetch1 = [[AEPTargetPrefetchObject alloc] initWithName:@"aep-loc-1" targetParameters:nil];
    AEPTargetPrefetchObject *prefetch2 = [[AEPTargetPrefetchObject alloc] initWithName:@"aep-loc-2" targetParameters:nil];
    [AEPMobileTarget prefetchContent:@[prefetch1, prefetch2] withParameters:nil callback:^(NSError * _Nullable error) {
        NSLog(@"================================================================================================");
        NSLog(@"error? >> %@", error.localizedDescription ?: @"nope");
    }];
}

- (IBAction)loadRequestWithContent:(id)sender {
    AEPTargetRequestObject *request1 = [[AEPTargetRequestObject alloc] initWithMboxName:@"aep-loc-1" defaultContent:@"defaultContent" targetParameters:nil contentCallback:^(NSString * _Nullable content) {
        NSLog(@"Content is >> %@", content ?: @"nope");
    }];
    AEPTargetRequestObject *request2 = [[AEPTargetRequestObject alloc] initWithMboxName:@"aep-loc-2" defaultContent:@"defaultContent2" targetParameters:nil contentCallback:^(NSString * _Nullable content) {
        NSLog(@"Content is >> %@", content ?: @"nope");
    }];
    [AEPMobileTarget retrieveLocationContent:@[request1, request2] withParameters:nil];
}

- (IBAction)loadRequestWithContentAndData:(id)sender {
    AEPTargetRequestObject *request1 = [[AEPTargetRequestObject alloc] initWithMboxName:@"aep-loc-1" defaultContent:@"defaultContent" targetParameters:nil contentWithDataCallback:^(NSString * _Nullable content, NSDictionary<NSString *,id> * _Nullable data) {
        NSLog(@"Content is >> %@", content ?: @"nope");
        
        if ([data objectForKey:@"responseTokens"]) {
            NSLog(@"Response Tokens are >> %@", data[@"responseTokens"]);
        }
        
        if ([data objectForKey:@"analytics.payload"]) {
            NSLog(@"Analytics payload is >> %@", data[@"analytics.payload"]);
        }
        
        if ([data objectForKey:@"clickmetric.analytics.payload"]) {
            NSLog(@"Click tracking Analytics payload is >> %@", data[@"clickmetric.analytics.payload"]);
        }
    }];
    AEPTargetRequestObject *request2 = [[AEPTargetRequestObject alloc] initWithMboxName:@"aep-loc-2" defaultContent:@"defaultContent2" targetParameters:nil contentWithDataCallback:^(NSString * _Nullable content, NSDictionary<NSString *,id> * _Nullable data) {
        NSLog(@"Content is >> %@", content ?: @"nope");
        
        if ([data objectForKey:@"responseTokens"]) {
            NSLog(@"Response Tokens are >> %@", data[@"responseTokens"]);
        }
        
        if ([data objectForKey:@"analytics.payload"]) {
            NSLog(@"Analytics payload is >> %@", data[@"analyticspayload"]);
        }
        
        if ([data objectForKey:@"clickmetric.analytics.payload"]) {
            NSLog(@"Click tracking Analytics payload is >> %@", data[@"clickmetric.analytics.payload"]);
        }
    }];
    [AEPMobileTarget retrieveLocationContent:@[request1, request2] withParameters:nil];
}

- (IBAction)locationDisplayedClicked:(id)sender {
    AEPTargetOrder *order = [[AEPTargetOrder alloc] initWithId:@"id1" total:1.0 purchasedProductIds:@[@"ppId1"]];
    AEPTargetProduct *product =[[AEPTargetProduct alloc] initWithProductId:@"pId1" categoryId:@"cId1"];
    AEPTargetParameters * targetParams = [[AEPTargetParameters alloc] initWithParameters:@{@"mbox_parameter_key":@"mbox_parameter_value"} profileParameters:@{@"name":@"Smith"} order:order product:product];
    [AEPMobileTarget displayedLocations:@[@"aep-loc-1", @"aep-loc-2"] withTargetParameters:targetParams];
}

- (IBAction)locationClicked:(id)sender {
    AEPTargetOrder *order = [[AEPTargetOrder alloc] initWithId:@"id1" total:1.0 purchasedProductIds:@[@"ppId1"]];
    AEPTargetProduct *product =[[AEPTargetProduct alloc] initWithProductId:@"pId1" categoryId:@"cId1"];
    AEPTargetParameters * targetParams = [[AEPTargetParameters alloc] initWithParameters:@{@"mbox_parameter_key":@"mbox_parameter_value"} profileParameters:@{@"name":@"Smith"} order:order product:product];
    
    [AEPMobileTarget clickedLocation:@"aep-loc-1" withTargetParameters:targetParams];
}

- (IBAction)resetExperienceClicked:(id)sender {
    [AEPMobileTarget resetExperience];
}

- (IBAction)clearPrefetch:(id)sender {
    [AEPMobileTarget clearPrefetchCache];
}

- (IBAction)getSessionIdClicked:(id)sender {
    [AEPMobileTarget getSessionId:^(NSString *sessionId, NSError *error){
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.lblSessionId setText:sessionId];
        });
    }];
}

- (IBAction)setSessionIdClicked:(id)sender {
    if(![_textSessionID.text isEqualToString:@""]) {
        [AEPMobileTarget setSessionId:_textSessionID.text];
    }
}

- (IBAction)getThirdPartyClicked:(id)sender {
    [AEPMobileTarget getThirdPartyId:^(NSString *thirdPartyID, NSError *error){
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.lblThirdParty setText:thirdPartyID];
        });
    }];
}

- (IBAction)setThirdPartyClicked:(id)sender {
    if(![_textThirdPartyID.text isEqualToString:@""]) {
        [AEPMobileTarget setThirdPartyId:_textThirdPartyID.text];
    }
}

- (IBAction)getTntIdClicked:(id)sender {
    [AEPMobileTarget getTntId:^(NSString *tntID, NSError *error){
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.lblTntId setText:tntID];
        });
    }];
}

- (IBAction)setTntIdClicked:(id)sender {
    if(![_textTntID.text isEqualToString:@""]) {
        [AEPMobileTarget setTntId:_textTntID.text];
    }
}

- (IBAction)startGriffon:(id)sender {
    if(![_griffonUrl.text isEqualToString:@""]) {
        [AEPMobileAssurance startSessionWithUrl:[NSURL URLWithString:_griffonUrl.text]];
    }
}

- (IBAction)enterPreviewMode:(id)sender {
    [AEPMobileCore collectLaunchInfo:@{@"adb_deeplink":@""}];
}

- (IBAction)setPreviewRestartDeeplink:(id)sender {
    [AEPMobileTarget setPreviewRestartDeepLink:[NSURL URLWithString:(@"http://www.adobe.com")]];
}

- (IBAction)executeRawRequest: (id)sender {
    NSDictionary *request = @{
        @"property": @{
            @"token": @"ccc7cdb3-c67a-6126-10b3-65d7f4d32b69"
        },
        @"execute": @{
            @"mboxes": @[
                @{
                    @"index": @(0),
                    @"name": @"aep-loc-1",
                    @"parameters": @{
                        @"mbox_parameter_key1": @"mbox_parameter_value1"
                    }
                },
                @{
                    @"index": @(1),
                    @"name": @"aep-loc-2",
                    @"parameters": @{
                        @"mbox_parameter_key2": @"mbox_parameter_value2"
                    }
                }
            ]
        }
    };

    [AEPMobileTarget executeRawRequest:request completion:^(NSDictionary<NSString *,id> * _Nullable data, NSError * _Nullable err) {
        if (err != nil) {
            NSLog(@"Error: %@", err);
            return;
        }
        NSLog(@"Execute raw response >> %@", data);
        NSDictionary* execute = data[@"execute"];
    
        NSArray* executeMboxes = (execute != nil) ? execute[@"mboxes"] : @[];
        for (int i = 0; i < [executeMboxes count]; i++) {
            NSString* mboxName = executeMboxes[i][@"name"];
            NSArray* metricsArr = executeMboxes[i][@"metrics"];
            NSString* token = [metricsArr count] ? metricsArr[0][@"eventToken"] : @"";
            if ([mboxName length] != 0 && [token length] != 0) {
                [self.notificationTokens addObject:@{ @"name": mboxName, @"token": token}];
            }
        }
    }];
}

- (IBAction)sendRawNotifications: (id)sender {
    NSMutableArray *notifications = [[NSMutableArray alloc] init];
    for (int i=0; i < [self.notificationTokens count]; i++) {
        NSDictionary* notification = @{
            @"id": [@(i) stringValue],
            @"timestamp": @((long)([[NSDate date] timeIntervalSince1970] * 1000.0)),
            @"type": @"click",
            @"mbox": @ {
                @"name": self.notificationTokens[i][@"name"],
            },
            @"tokens": @[self.notificationTokens[i][@"token"]],
            @"parameters": @{
                @"mbox_parameter_key3": @"mbox_parameter_value3"
            }
        };
        [notifications addObject:notification];
    }
    if ([notifications count] == 0) {
        return;
    }
    NSDictionary *request = @{
        @"notifications": notifications
    };
    [AEPMobileTarget sendRawNotifications:request];
    [self.notificationTokens removeAllObjects];
}
@end
