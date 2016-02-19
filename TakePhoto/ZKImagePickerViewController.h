//
//  ZKImagePickerViewController.h
//  TakePhoto
//
//  Created by ZK on 16/1/28.
//  Copyright © 2016年 ZK. All rights reserved.
//

#import <UIKit/UIKit.h>
@class ZKImagePickerViewController;

@protocol ZKImagePickerViewControllerDelegate <NSObject>

- (void)imagePickerController:(ZKImagePickerViewController *)imagePicker didFinishPickingImage:(UIImage *)image;

@end

@interface ZKImagePickerViewController : UIViewController

@property (nonatomic, weak) id <ZKImagePickerViewControllerDelegate> delegate;

@end
