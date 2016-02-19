//
//  ZKImagePickerViewController.m
//  TakePhoto
//
//  Created by ZK on 16/1/28.
//  Copyright © 2016年 ZK. All rights reserved.
//

@import AVFoundation;
@import Photos;

#import "ZKImagePickerViewController.h"
#import "ZKPickerImageCompleteViewController.h"

static void * CapturingStillImageContext = &CapturingStillImageContext;
static void * SessionRunningContext = &SessionRunningContext;

typedef NS_ENUM( NSInteger, AVCamSetupResult ) {
    AVCamSetupResultSuccess,
    AVCamSetupResultCameraNotAuthorized,
    AVCamSetupResultSessionConfigurationFailed
};

@interface ZKImagePickerViewController () <ZKPickerImageCompleteViewControllerDelegate>

//在 storyboard 里面可以找到这些属性
@property (weak, nonatomic) IBOutlet UIButton *stillButton;
@property (weak, nonatomic) IBOutlet UIView *previewView;

//闪光灯按钮
@property (nonatomic, strong) UIButton *flashButton;
//切换相机按钮
@property (nonatomic, strong) UIButton *cameraButton;

//PreviewLayer 用来显示相机捕获到的图像
@property (nonatomic, strong) AVCaptureVideoPreviewLayer *previewLayer;

//Session management.
@property (nonatomic) dispatch_queue_t sessionQueue;
@property (nonatomic) AVCaptureSession *session;
@property (nonatomic) AVCaptureDeviceInput *videoDeviceInput;
@property (nonatomic) AVCaptureStillImageOutput *stillImageOutput;

//Utilities.
@property (nonatomic) AVCamSetupResult setupResult;
@property (nonatomic, getter=isSessionRunning) BOOL sessionRunning;
@property (nonatomic, assign) AVCaptureFlashMode flashMode;
@property (nonatomic, strong) UIImageView *fouceImageView;

@end

@implementation ZKImagePickerViewController

- (void)viewDidLoad {
    [super viewDidLoad];

    [self initConfig];
    
    [self checkAuthorizationStatus];
    
    [self setupSessionConfig];
}

- (void)initConfig {
    UINavigationBar *bar = [UINavigationBar appearance];
    bar.translucent = NO;
    bar.barTintColor = [UIColor blackColor];
    
    self.cameraButton = [UIButton buttonWithType:UIButtonTypeCustom];
    UIImage *switchCameraImage = [UIImage imageNamed:@"switch_over"];
    self.cameraButton.frame = CGRectMake(0, 0, switchCameraImage.size.width / 2, switchCameraImage.size.height / 2);
    [self.cameraButton setImage:switchCameraImage forState:UIControlStateNormal];
    [self.cameraButton addTarget:self action:@selector(changeCamera:) forControlEvents:UIControlEventTouchUpInside];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithCustomView:self.cameraButton];
    
    self.flashButton = [UIButton buttonWithType:UIButtonTypeCustom];
    UIImage *switchTorchImage = [UIImage imageNamed:@"torch_off"];
    self.flashButton.frame = CGRectMake(0, 0, switchTorchImage.size.width / 2, switchTorchImage.size.height / 2);
    [self.flashButton setImage:switchTorchImage forState:UIControlStateNormal];
    [self.flashButton addTarget:self action:@selector(changeFlash:) forControlEvents:UIControlEventTouchUpInside];
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithCustomView:self.flashButton];
    
    //当 session 启动后，拍照按钮才可以点击
    self.cameraButton.enabled = NO;
    self.flashButton.enabled = NO;
    self.stillButton.enabled = NO;
    
    //创建 AVCaptureSession.
    self.session = [[AVCaptureSession alloc] init];
    
    //Setup the preview Layer.
    self.previewLayer = [[AVCaptureVideoPreviewLayer alloc] initWithSession:self.session];
    self.previewLayer.frame = CGRectMake(0, 0, self.view.bounds.size.width, self.view.bounds.size.width);
    self.previewLayer.videoGravity = AVLayerVideoGravityResizeAspectFill;
    [self.previewView.layer addSublayer:self.previewLayer];
    
    //AVCaptureSession 和与 AVCaptureSession 操作的相关对象放在这个队列中处理，避免阻塞主线程
    self.sessionQueue = dispatch_queue_create( "session queue", DISPATCH_QUEUE_SERIAL );
    
    self.setupResult = AVCamSetupResultSuccess;
    
    //闪光灯默认为自动打开，由系统来调度
    self.flashMode = AVCaptureFlashModeAuto;
}

- (void)checkAuthorizationStatus {
    //检查拍照的权限
    switch ( [AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeVideo] ) {
        case AVAuthorizationStatusAuthorized: {
            //用户已经授权
            break;
        }
        case AVAuthorizationStatusNotDetermined: {
            //如果没有拍照权限，就先挂起 sessionQueue 队列，发起一次授权请求
            dispatch_suspend( self.sessionQueue );
            [AVCaptureDevice requestAccessForMediaType:AVMediaTypeVideo completionHandler:^( BOOL granted ) {
                if ( ! granted ) {
                    self.setupResult = AVCamSetupResultCameraNotAuthorized;
                }
                dispatch_resume( self.sessionQueue );
            }];
            break;
        }
        default: {
            // The user has previously denied access.
            self.setupResult = AVCamSetupResultCameraNotAuthorized;
            break;
        }
    }
}

- (void)setupSessionConfig {
    // Setup the capture session.
    // In general it is not safe to mutate an AVCaptureSession or any of its inputs, outputs, or connections from multiple threads at the same time.
    // Why not do all of this on the main queue?
    // Because -[AVCaptureSession startRunning] is a blocking call which can take a long time. We dispatch session setup to the sessionQueue
    // so that the main queue isn't blocked, which keeps the UI responsive.
    dispatch_async( self.sessionQueue, ^{
        if ( self.setupResult != AVCamSetupResultSuccess ) {
            return;
        }
        
        NSError *error = nil;
        
        AVCaptureDevice *videoDevice = [ZKImagePickerViewController deviceWithMediaType:AVMediaTypeVideo preferringPosition:AVCaptureDevicePositionBack];
        AVCaptureDeviceInput *videoDeviceInput = [AVCaptureDeviceInput deviceInputWithDevice:videoDevice error:&error];
        
        if ( ! videoDeviceInput ) {
            NSLog( @"Could not create video device input: %@", error );
        }
        
        [self.session beginConfiguration];
        
        if ( [self.session canAddInput:videoDeviceInput] ) {
            [self.session addInput:videoDeviceInput];
            self.videoDeviceInput = videoDeviceInput;
            
            dispatch_async( dispatch_get_main_queue(), ^{
                // Why are we dispatching this to the main queue?
                // Because AVCaptureVideoPreviewLayer is the backing layer for PreviewView and UIView
                // can only be manipulated on the main thread.
                // Note: As an exception to the above rule, it is not necessary to serialize video orientation changes
                // on the AVCaptureVideoPreviewLayer’s connection with other session manipulation.
                
                // Use the status bar orientation as the initial video orientation. Subsequent orientation changes are handled by
                // -[viewWillTransitionToSize:withTransitionCoordinator:].
                UIInterfaceOrientation statusBarOrientation = [UIApplication sharedApplication].statusBarOrientation;
                AVCaptureVideoOrientation initialVideoOrientation = AVCaptureVideoOrientationPortrait;
                if ( statusBarOrientation != UIInterfaceOrientationUnknown ) {
                    initialVideoOrientation = (AVCaptureVideoOrientation)statusBarOrientation;
                }
                
                self.previewLayer.connection.videoOrientation = initialVideoOrientation;
            } );
        }
        else {
            NSLog( @"Could not add video device input to the session" );
            self.setupResult = AVCamSetupResultSessionConfigurationFailed;
        }
        
        AVCaptureStillImageOutput *stillImageOutput = [[AVCaptureStillImageOutput alloc] init];
        if ( [self.session canAddOutput:stillImageOutput] ) {
            stillImageOutput.outputSettings = @{AVVideoCodecKey : AVVideoCodecJPEG};
            [self.session addOutput:stillImageOutput];
            self.stillImageOutput = stillImageOutput;
        } else {
            NSLog( @"Could not add still image output to the session" );
            self.setupResult = AVCamSetupResultSessionConfigurationFailed;
        }
        
        [self.session commitConfiguration];
    } );
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    
    dispatch_async( self.sessionQueue, ^{
        switch ( self.setupResult ) {
            case AVCamSetupResultSuccess: {
                // Only setup observers and start the session running if setup succeeded.
                [self addObservers];
                [self.session startRunning];
                self.sessionRunning = self.session.isRunning;
                break;
            }
            case AVCamSetupResultCameraNotAuthorized: {
                dispatch_async( dispatch_get_main_queue(), ^{
                    NSString *message = @"您的相机未授权，请授权";
                    UIAlertController *alertController = [UIAlertController alertControllerWithTitle:@"提示" message:message preferredStyle:UIAlertControllerStyleAlert];
                    
                    // Provide quick access to Settings.
                    UIAlertAction *settingsAction = [UIAlertAction actionWithTitle:@"去设置" style:UIAlertActionStyleDefault handler:^( UIAlertAction *action ) {
                        [[UIApplication sharedApplication] openURL:[NSURL URLWithString:UIApplicationOpenSettingsURLString]];
                    }];
                    [alertController addAction:settingsAction];
                    [self presentViewController:alertController animated:YES completion:nil];
                } );
                break;
            }
            case AVCamSetupResultSessionConfigurationFailed: {
                dispatch_async( dispatch_get_main_queue(), ^{
                    NSString *message = @"不能够拍照，未知错误，请重试";
                    UIAlertController *alertController = [UIAlertController alertControllerWithTitle:@"提示" message:message preferredStyle:UIAlertControllerStyleAlert];
                    UIAlertAction *cancelAction = [UIAlertAction actionWithTitle:@"好的" style:UIAlertActionStyleCancel handler:^(UIAlertAction * _Nonnull action) {
                        [self dismissViewController];
                    }];
                    [alertController addAction:cancelAction];
                    [self presentViewController:alertController animated:YES completion:nil];
                } );
                break;
            }
        }
    } );
}

- (void)viewDidDisappear:(BOOL)animated {
    dispatch_async( self.sessionQueue, ^{
        if ( self.setupResult == AVCamSetupResultSuccess ) {
            [self.session stopRunning];
            [self removeObservers];
        }
    } );
    
    [super viewDidDisappear:animated];
}

#pragma mark KVO and Notifications

- (void)addObservers {
    [self.session addObserver:self forKeyPath:@"running" options:NSKeyValueObservingOptionNew context:SessionRunningContext];
    [self.stillImageOutput addObserver:self forKeyPath:@"capturingStillImage" options:NSKeyValueObservingOptionNew context:CapturingStillImageContext];
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(subjectAreaDidChange:) name:AVCaptureDeviceSubjectAreaDidChangeNotification object:self.videoDeviceInput.device];
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(sessionRuntimeError:) name:AVCaptureSessionRuntimeErrorNotification object:self.session];
}

- (void)removeObservers {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    
    [self.session removeObserver:self forKeyPath:@"running" context:SessionRunningContext];
    [self.stillImageOutput removeObserver:self forKeyPath:@"capturingStillImage" context:CapturingStillImageContext];
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
    if ( context == CapturingStillImageContext ) {
        BOOL isCapturingStillImage = [change[NSKeyValueChangeNewKey] boolValue];
        
        if ( isCapturingStillImage ) {
            dispatch_async( dispatch_get_main_queue(), ^{
                self.previewView.layer.opacity = 0.0;
                [UIView animateWithDuration:0.25 animations:^{
                    self.previewView.layer.opacity = 1.0;
                }];
            } );
        }
    } else if ( context == SessionRunningContext ) {
        BOOL isSessionRunning = [change[NSKeyValueChangeNewKey] boolValue];
        
        dispatch_async( dispatch_get_main_queue(), ^{
            // Only enable the ability to change camera if the device has more than one camera.
            self.cameraButton.enabled = isSessionRunning && ( [AVCaptureDevice devicesWithMediaType:AVMediaTypeVideo].count > 1 );
            self.flashButton.enabled = isSessionRunning;
            self.stillButton.enabled = isSessionRunning;
        } );
    } else {
        [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
    }
}

- (void)subjectAreaDidChange:(NSNotification *)notification {
    CGPoint devicePoint = CGPointMake( 0.5, 0.5 );
    [self focusWithMode:AVCaptureFocusModeContinuousAutoFocus exposeWithMode:AVCaptureExposureModeContinuousAutoExposure atDevicePoint:devicePoint monitorSubjectAreaChange:NO];
}

#pragma mark Device Configuration
- (void)focusWithMode:(AVCaptureFocusMode)focusMode exposeWithMode:(AVCaptureExposureMode)exposureMode atDevicePoint:(CGPoint)point monitorSubjectAreaChange:(BOOL)monitorSubjectAreaChange {
    dispatch_async( self.sessionQueue, ^{
        AVCaptureDevice *device = self.videoDeviceInput.device;
        NSError *error = nil;
        if ( [device lockForConfiguration:&error] ) {
            
            // Setting (focus/exposure)PointOfInterest alone does not initiate a (focus/exposure) operation.
            // Call -set(Focus/Exposure)Mode: to apply the new point of interest.
            if ( device.isFocusPointOfInterestSupported && [device isFocusModeSupported:focusMode] ) {
                device.focusPointOfInterest = point;
                device.focusMode = focusMode;
            }
            
            if ( device.isExposurePointOfInterestSupported && [device isExposureModeSupported:exposureMode] ) {
                device.exposurePointOfInterest = point;
                device.exposureMode = exposureMode;
            }
            
            device.subjectAreaChangeMonitoringEnabled = monitorSubjectAreaChange;
            [device unlockForConfiguration];
        } else {
            NSLog( @"Could not lock device for configuration: %@", error );
        }
    } );
}

- (void)sessionRuntimeError:(NSNotification *)notification {
    NSError *error = notification.userInfo[AVCaptureSessionErrorKey];
    NSLog( @"Capture session runtime error: %@", error );
    
    // Automatically try to restart the session running if media services were reset and the last start running succeeded.
    // Otherwise, enable the user to try to resume the session running.
    if ( error.code == AVErrorMediaServicesWereReset ) {
        dispatch_async( self.sessionQueue, ^{
            if ( self.isSessionRunning ) {
                [self.session startRunning];
                self.sessionRunning = self.session.isRunning;
            } else {
                [self sessionExceptionHandler];
            }
        } );
    } else {
        [self sessionExceptionHandler];
    }
}

- (void)sessionExceptionHandler {
    //确保是在主线程调用
    dispatch_async( dispatch_get_main_queue(), ^{
        NSString *message = @"相机发生未知错误";
        UIAlertController *alertController = [UIAlertController alertControllerWithTitle:@"提示" message:message preferredStyle:UIAlertControllerStyleAlert];
        UIAlertAction *cancelAction = [UIAlertAction actionWithTitle:@"尝试重启相机" style:UIAlertActionStyleCancel handler:^(UIAlertAction * _Nonnull action) {
            dispatch_async( self.sessionQueue, ^{
                // The session might fail to start running, e.g., if a phone or FaceTime call is still using audio or video.
                // A failure to start the session running will be communicated via a session runtime error notification.
                // To avoid repeatedly failing to start the session running, we only try to restart the session running in the
                // session runtime error handler if we aren't trying to resume the session running.
                [self.session startRunning];
                self.sessionRunning = self.session.isRunning;
                if ( ! self.session.isRunning ) {
                    dispatch_async( dispatch_get_main_queue(), ^{
                        NSString *message = @"重启失败，尝试重新打开相机";
                        UIAlertController *alertController = [UIAlertController alertControllerWithTitle:@"提示" message:message preferredStyle:UIAlertControllerStyleAlert];
                        UIAlertAction *cancelAction = [UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleCancel handler:^(UIAlertAction * _Nonnull action) {
                            [self dismissViewController];
                        }];
                        [alertController addAction:cancelAction];
                        [self presentViewController:alertController animated:YES completion:nil];
                    } );
                }
            } );
        }];
        [alertController addAction:cancelAction];
        [self presentViewController:alertController animated:YES completion:nil];
    } );
}

- (IBAction)snapStillImage:(UIButton *)sender {
    dispatch_async( self.sessionQueue, ^{
        AVCaptureConnection *connection = [self.stillImageOutput connectionWithMediaType:AVMediaTypeVideo];
        
        // Update the orientation on the still image output video connection before capturing.
        connection.videoOrientation = self.previewLayer.connection.videoOrientation;
        
        // Flash set to Auto for Still Capture.
        [ZKImagePickerViewController setFlashMode:self.flashMode forDevice:self.videoDeviceInput.device];
        
        // Capture a still image.
        [self.stillImageOutput captureStillImageAsynchronouslyFromConnection:connection completionHandler:^( CMSampleBufferRef imageDataSampleBuffer, NSError *error ) {
            if ( imageDataSampleBuffer ) {
                // The sample buffer is not retained. Create image data before saving the still image to the photo library asynchronously.
                NSData *imageData = [AVCaptureStillImageOutput jpegStillImageNSDataRepresentation:imageDataSampleBuffer];
                UIImage *image = [UIImage imageWithData:imageData];
                
                //截取部分图像，原因 AVCaptureVideoPreviewLayer 呈现出来的图像并不是 AVCaptureStillImageOutput 输出的图像
                //AVCaptureStillImageOutput 输出的永远是相机捕获到的整个画面
                CGRect newRect = CGRectMake((image.size.height - image.size.width) / 2, 0, image.size.width, image.size.width);
                CGImageRef subImageRef = CGImageCreateWithImageInRect(image.CGImage, newRect);
                image = [UIImage imageWithCGImage:subImageRef scale:0 orientation:UIImageOrientationRight];
                CFRelease(subImageRef);
        
                ZKPickerImageCompleteViewController *pickerImageCompleteVc = [[ZKPickerImageCompleteViewController alloc] init];
                pickerImageCompleteVc.image = image;
                pickerImageCompleteVc.delegate = self;
                [self.navigationController pushViewController:pickerImageCompleteVc animated:NO];
            } else {
                NSLog( @"Could not capture still image: %@", error );
            }
        }];
    } );
}

- (void)changeCamera:(UIButton *)sender {
    self.cameraButton.enabled = NO;
    self.flashButton.enabled = NO;
    self.stillButton.enabled = NO;
    
    dispatch_async( self.sessionQueue, ^{
        AVCaptureDevice *currentVideoDevice = self.videoDeviceInput.device;
        AVCaptureDevicePosition preferredPosition = AVCaptureDevicePositionUnspecified;
        AVCaptureDevicePosition currentPosition = currentVideoDevice.position;
        
        switch ( currentPosition ) {
            case AVCaptureDevicePositionUnspecified:
            case AVCaptureDevicePositionFront:
                preferredPosition = AVCaptureDevicePositionBack;
                break;
            case AVCaptureDevicePositionBack:
                preferredPosition = AVCaptureDevicePositionFront;
                break;
        }
        
        AVCaptureDevice *videoDevice = [ZKImagePickerViewController deviceWithMediaType:AVMediaTypeVideo preferringPosition:preferredPosition];
        AVCaptureDeviceInput *videoDeviceInput = [AVCaptureDeviceInput deviceInputWithDevice:videoDevice error:nil];
        
        [self.session beginConfiguration];
        
        // Remove the existing device input first, since using the front and back camera simultaneously is not supported.
        [self.session removeInput:self.videoDeviceInput];
        
        if ( [self.session canAddInput:videoDeviceInput] ) {
            [[NSNotificationCenter defaultCenter] removeObserver:self name:AVCaptureDeviceSubjectAreaDidChangeNotification object:currentVideoDevice];
            
            [ZKImagePickerViewController setFlashMode:AVCaptureFlashModeAuto forDevice:videoDevice];
            [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(subjectAreaDidChange:) name:AVCaptureDeviceSubjectAreaDidChangeNotification object:videoDevice];
            
            [self.session addInput:videoDeviceInput];
            self.videoDeviceInput = videoDeviceInput;
        } else {
            [self.session addInput:self.videoDeviceInput];
        }
        
        [self.session commitConfiguration];
        
        dispatch_async( dispatch_get_main_queue(), ^{
            self.cameraButton.enabled = YES;
            self.stillButton.enabled = YES;
            
            //只有是后置摄像头闪光灯按钮才可以点击
            if (preferredPosition == AVCaptureDevicePositionBack) {
                self.flashButton.enabled = YES;
            }
        } );
    } );
}

- (void)changeFlash:(UIButton *)sender {
    if (self.flashMode != AVCaptureFlashModeOn) {
        self.flashMode = AVCaptureFlashModeOn;
        [self.flashButton setImage:[UIImage imageNamed:@"torch_on"] forState:UIControlStateNormal];
    } else {
        self.flashMode = AVCaptureFlashModeAuto;
        [self.flashButton setImage:[UIImage imageNamed:@"torch_off"] forState:UIControlStateNormal];
    }
}

- (IBAction)focusAndExposeTap:(UITapGestureRecognizer *)gestureRecognizer {
    CGPoint pointInPreview = [gestureRecognizer locationInView:gestureRecognizer.view];
    CGPoint devicePoint = [self.previewLayer captureDevicePointOfInterestForPoint:pointInPreview];
    [self focusWithMode:AVCaptureFocusModeAutoFocus exposeWithMode:AVCaptureExposureModeAutoExpose atDevicePoint:devicePoint monitorSubjectAreaChange:YES];
    
    if (!self.fouceImageView) {
        self.fouceImageView = [[UIImageView alloc] initWithImage:[UIImage imageNamed:@"fouce_position"]];
    } else {
        [self.fouceImageView removeFromSuperview];
    }

    self.fouceImageView.center = pointInPreview;
    [self.previewView addSubview:self.fouceImageView];
    
    __weak typeof(self) weakSelf = self;
    [UIView animateWithDuration:0.7 animations:^{
        weakSelf.fouceImageView.transform = CGAffineTransformMakeScale(0.7f, 0.7f);
    } completion:^(BOOL finished) {
        [self.fouceImageView removeFromSuperview];
        self.fouceImageView.transform = CGAffineTransformIdentity;
    }];
}

+ (AVCaptureDevice *)deviceWithMediaType:(NSString *)mediaType preferringPosition:(AVCaptureDevicePosition)position {
    NSArray *devices = [AVCaptureDevice devicesWithMediaType:mediaType];
    AVCaptureDevice *captureDevice = devices.firstObject;
    
    for ( AVCaptureDevice *device in devices ) {
        if ( device.position == position ) {
            captureDevice = device;
            break;
        }
    }
    
    return captureDevice;
}

+ (void)setFlashMode:(AVCaptureFlashMode)flashMode forDevice:(AVCaptureDevice *)device {
    if ( device.hasFlash && [device isFlashModeSupported:flashMode] ) {
        NSError *error = nil;
        if ( [device lockForConfiguration:&error] ) {
            device.flashMode = flashMode;
            [device unlockForConfiguration];
        } else {
            NSLog( @"Could not lock device for configuration: %@", error );
        }
    }
}

- (void)dismissViewController {
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)pickerImageComplete:(ZKPickerImageCompleteViewController *)pickerImageCompleteVc {
    if ([self.delegate respondsToSelector:@selector(imagePickerController:didFinishPickingImage:)]) {
        [self.delegate imagePickerController:self didFinishPickingImage:pickerImageCompleteVc.image];
    }
}

@end
