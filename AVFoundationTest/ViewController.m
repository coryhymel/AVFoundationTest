//
//  ViewController.m
//  AVFoundationTest
//
//  Created by Cory Hymel on 5/13/14.
//  Copyright (c) 2014 Simble. All rights reserved.
//

#import "ViewController.h"

#import <AVFoundation/AVFoundation.h>

#include <sys/sysctl.h>
#include <sys/types.h>
#include <mach/mach.h>
#include <mach/processor_info.h>
#include <mach/mach_host.h>

//How ofter we check CPU usage (in seconds)
#define kCPUUpdateThreshold 1.0

@interface ViewController () {
    
    processor_info_array_t cpuInfo, prevCpuInfo;
    
    mach_msg_type_number_t numCpuInfo, numPrevCpuInfo;
    
    unsigned numCPUs;
    
    NSTimer *updateTimer;
    NSLock  *CPUUsageLock;
}

@property (nonatomic) UILabel *core1Label, *core2Label;

@property (nonatomic) UIToolbar *toolbar;

@property (nonatomic) AVCaptureSession           *captureSession;
@property (nonatomic) AVCaptureVideoPreviewLayer *captureVideoPreviewLayer;
@end

@implementation ViewController



- (void)updateInfo:(NSTimer *)timer
{
    natural_t numCPUsU = 0U;
    kern_return_t err  = host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &numCPUsU, &cpuInfo, &numCpuInfo);
   
    if(err == KERN_SUCCESS) {
       
        [CPUUsageLock lock];
        
        for(unsigned i = 0U; i < numCPUs; ++i) {
            
            float inUse, total;
           
            if(prevCpuInfo) {
                inUse = (
                         (cpuInfo[(CPU_STATE_MAX * i) + CPU_STATE_USER]   - prevCpuInfo[(CPU_STATE_MAX * i) + CPU_STATE_USER])
                         + (cpuInfo[(CPU_STATE_MAX * i) + CPU_STATE_SYSTEM] - prevCpuInfo[(CPU_STATE_MAX * i) + CPU_STATE_SYSTEM])
                         + (cpuInfo[(CPU_STATE_MAX * i) + CPU_STATE_NICE]   - prevCpuInfo[(CPU_STATE_MAX * i) + CPU_STATE_NICE])
                         );
                total = inUse + (cpuInfo[(CPU_STATE_MAX * i) + CPU_STATE_IDLE] - prevCpuInfo[(CPU_STATE_MAX * i) + CPU_STATE_IDLE]);
            } else {
                inUse = cpuInfo[(CPU_STATE_MAX * i) + CPU_STATE_USER] + cpuInfo[(CPU_STATE_MAX * i) + CPU_STATE_SYSTEM] + cpuInfo[(CPU_STATE_MAX * i) + CPU_STATE_NICE];
                total = inUse + cpuInfo[(CPU_STATE_MAX * i) + CPU_STATE_IDLE];
            }
            
   
            if (i == 0)
                self.core1Label.text = [NSString stringWithFormat:@"Core 1\nUsage: %f", inUse/ total];
            else if (i == 1)
                self.core2Label.text = [NSString stringWithFormat:@"Core 2\nUsage: %f", inUse/ total];
        }
       
        [CPUUsageLock unlock];
        
        if(prevCpuInfo) {
            size_t prevCpuInfoSize = sizeof(integer_t) * numPrevCpuInfo;
            vm_deallocate(mach_task_self(), (vm_address_t)prevCpuInfo, prevCpuInfoSize);
        }
        
        prevCpuInfo = cpuInfo;
        numPrevCpuInfo = numCpuInfo;
        
        cpuInfo = NULL;
        numCpuInfo = 0U;
    }
    
    else {
        NSLog(@"wa wa wa we got an ERROR!");
    }
}

- (void)initCapture
{
    AVCaptureDevice       *inputDevice = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
    AVCaptureDeviceInput *captureInput = [AVCaptureDeviceInput deviceInputWithDevice:inputDevice error:nil];
   
    if (!captureInput) {
        return;
    }
    
    AVCaptureVideoDataOutput *captureOutput = [[AVCaptureVideoDataOutput alloc] init];

    NSString *key   = (NSString*)kCVPixelBufferPixelFormatTypeKey;
    NSNumber *value = [NSNumber numberWithUnsignedInt:kCVPixelFormatType_32BGRA];
   
    NSDictionary* videoSettings = [NSDictionary dictionaryWithObject:value forKey:key];
    
    [captureOutput setVideoSettings:videoSettings];
    
    self.captureSession = [[AVCaptureSession alloc] init];
    
    NSString* preset = 0;
    
    if (!preset) {
        preset = AVCaptureSessionPresetMedium;
    }
    
    self.captureSession.sessionPreset = preset;
    
    if ([self.captureSession canAddInput:captureInput]) {
        [self.captureSession addInput:captureInput];
    }
   
    if ([self.captureSession canAddOutput:captureOutput]) {
        [self.captureSession addOutput:captureOutput];
    }
    
    //handle prevLayer...i guess you should technically do this in an async block to keep ui smooth but w/e for a demo
    if (!self.captureVideoPreviewLayer) {
        self.captureVideoPreviewLayer = [AVCaptureVideoPreviewLayer layerWithSession:self.captureSession];
    }
    
    //if you want to adjust the previewlayer frame, here!
    self.captureVideoPreviewLayer.frame = self.view.bounds;
   
    self.captureVideoPreviewLayer.videoGravity = AVLayerVideoGravityResizeAspectFill;
    
    [self.view.layer addSublayer: self.captureVideoPreviewLayer];
    
    [self.captureSession startRunning];
    
    [self addToolbar];
}

- (void)addToolbar {
    self.toolbar = [[UIToolbar alloc] initWithFrame:self.view.frame];
    [self.view addSubview:self.toolbar];
    
    [self startMonitoringCPUUsage];
}

- (void)startMonitoringCPUUsage {

    self.core1Label = [[UILabel alloc] initWithFrame:CGRectMake(0, 100, CGRectGetWidth(self.view.bounds), 100)];
    self.core2Label = [[UILabel alloc] initWithFrame:CGRectMake(0, 300, CGRectGetWidth(self.view.bounds), 100)];
    
    self.core1Label.numberOfLines = 0;
    self.core2Label.numberOfLines = 0;
    
    self.core1Label.textAlignment = NSTextAlignmentCenter;
    self.core2Label.textAlignment = NSTextAlignmentCenter;
    
    self.core1Label.font = [UIFont fontWithName:@"HelveticaNeue-Light" size:20];
    self.core2Label.font = [UIFont fontWithName:@"HelveticaNeue-Light" size:20];
    
    [self.view addSubview:self.core1Label];
    [self.view addSubview:self.core2Label];
    
    int mib[2U] = { CTL_HW, HW_NCPU };
    
    size_t sizeOfNumCPUs = sizeof(numCPUs);
   
    int status  = sysctl(mib, 2U, &numCPUs, &sizeOfNumCPUs, NULL, 0U);
    
    if(status) numCPUs = 1;
    
    CPUUsageLock = [[NSLock alloc] init];
    
    updateTimer  = [NSTimer scheduledTimerWithTimeInterval:kCPUUpdateThreshold
                                                    target:self
                                                  selector:@selector(updateInfo:)
                                                  userInfo:nil
                                                   repeats:YES];
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    [self initCapture];
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

@end
