//
//  ZKPickerImageCompleteViewController.m
//  TakePhoto
//
//  Created by ZK on 16/2/2.
//  Copyright © 2016年 ZK. All rights reserved.
//

#import "ZKPickerImageCompleteViewController.h"

@interface ZKPickerImageCompleteViewController ()

@property (weak, nonatomic) IBOutlet UIImageView *imageView;

@end

@implementation ZKPickerImageCompleteViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithCustomView:[UIView new]];
    self.imageView.image = self.image;
}

- (IBAction)repickerImage:(UIButton *)sender {
    [self.navigationController popViewControllerAnimated:NO];
}

- (IBAction)userPhoto:(UIButton *)sender {
    if ([self.delegate respondsToSelector:@selector(pickerImageComplete:)]) {
        [self.delegate pickerImageComplete:self];
    }
}

@end
