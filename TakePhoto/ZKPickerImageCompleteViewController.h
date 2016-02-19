//
//  ZKPickerImageCompleteViewController.h
//  TakePhoto
//
//  Created by ZK on 16/2/2.
//  Copyright © 2016年 ZK. All rights reserved.
//

#import <UIKit/UIKit.h>
@class ZKPickerImageCompleteViewController;

@protocol ZKPickerImageCompleteViewControllerDelegate <NSObject>

- (void)pickerImageComplete:(ZKPickerImageCompleteViewController *)pickerImageCompleteVc;

@end

@interface ZKPickerImageCompleteViewController : UIViewController

@property (nonatomic, weak) id <ZKPickerImageCompleteViewControllerDelegate> delegate;
@property (nonatomic, strong) UIImage *image;

@end
