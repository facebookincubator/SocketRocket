//
// Copyright 2012 Square Inc.
// Portions Copyright (c) 2016-present, Facebook, Inc.
// All rights reserved.
//
// This source code is licensed under the license found in the
// LICENSE-examples file in the root directory of this source tree.
//

#import <UIKit/UIKit.h>

@interface TCViewController : UITableViewController

@property (nonatomic, strong) IBOutlet UITextView *inputView;

- (IBAction)reconnect:(id)sender;
- (IBAction)sendPing:(id)sender;

@end
