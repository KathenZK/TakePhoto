//
//  ViewController.m
//  TakePhoto
//
//  Created by ZK on 16/1/25.
//  Copyright © 2016年 ZK. All rights reserved.
//

#import "ViewController.h"
#import "ZKImagePickerViewController.h"

@interface ViewController ()

@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
}

- (IBAction)takePhoto:(UIButton *)sender {
    ZKImagePickerViewController *imagePickerVc = [[UIStoryboard storyboardWithName:@"ZKImagePickerViewController" bundle:nil] instantiateInitialViewController];
    [self presentViewController:imagePickerVc animated:YES completion:nil];
}

@end
