//
//  RLMBMainWindowController.m
//  RealmBrowser
//
//  Created by Gustaf Kugelberg on 20/11/14.
//  Copyright (c) 2014 Realm inc. All rights reserved.
//

#import "RLMBMainWindowController.h"

#import <Realm/Realm.h>
#import "RLMBHeaders_Private.h"

#import "RLMBPaneViewController.h"
#import "RLMBRootPaneViewController.h"

#import "RLMBSidebarCellView.h"


NSString *const kRLMBRightMostConstraint = @"RLMBRightMostConstraint";
CGFloat const kRLMBPaneMargin = 50;

@interface RLMBMainWindowController () <RLMBCanvasDelegate, NSTableViewDataSource, NSTableViewDelegate>

@property (nonatomic) RLMRealm *realm;
@property (nonatomic) NSMutableArray *objectClasses;

@property (weak) IBOutlet NSScrollView *scrollView;
@property (weak) IBOutlet NSTableView *sidebarTableView;

@property (nonatomic) NSView *canvas;

@property (nonatomic) NSMutableArray *panes;
@property (nonatomic, readonly) RLMBRootPaneViewController *rootPane;

@end


@implementation RLMBMainWindowController

- (instancetype)initWithWindow:(NSWindow *)window
{
    self = [super initWithWindow:window];
    if (self) {
        [self setup];
    }
    return self;
}

- (void)setup
{
    self.panes = [NSMutableArray array];
}

- (void)windowDidLoad {
    [super windowDidLoad];
    
    self.window.titleVisibility = NSWindowTitleHidden;
    
    self.canvas = [[NSView alloc] init];
    self.canvas.translatesAutoresizingMaskIntoConstraints = NO;
    
    self.scrollView.documentView = self.canvas;
    
    NSDictionary *views = NSDictionaryOfVariableBindings(_canvas);
    NSArray *hConstraints = [NSLayoutConstraint constraintsWithVisualFormat:@"H:|[_canvas]"
                                                                    options:0
                                                                    metrics:nil
                                                                      views:views];
    
    NSArray *vConstraints = [NSLayoutConstraint constraintsWithVisualFormat:@"V:|[_canvas]|"
                                                                    options:0
                                                                    metrics:nil
                                                                      views:views];
    
    [self.scrollView.contentView addConstraints:hConstraints];
    [self.scrollView.contentView addConstraints:vConstraints];
}

- (void)updateWithRealm:(RLMRealm *)realm
{
    self.realm = realm;
    
    NSMutableArray *objectClasses = [NSMutableArray array];
    for (RLMObjectSchema *objectSchema in self.realm.schema.objectSchema) {
        RLMResults *objects = [self.realm allObjects:objectSchema.className];
        [objectClasses addObject:objects];
    }
    
    self.objectClasses = objectClasses;
}

- (RLMBPaneViewController *)addPaneAfterPane:(RLMBPaneViewController *)pane
{
    [self removePanesAfterPane:pane];
    
    RLMBPaneViewController *newPane = [[RLMBPaneViewController alloc] initWithNibName:@"RLMBPaneViewController" bundle:nil];
    [self addPane:newPane];
    return newPane;
}

- (void)addPane:(RLMBPaneViewController *)pane
{
    [self.canvas addSubview:pane.view];
    [self addSizeConstraintsTo:pane.view within:self.canvas];
    [self.canvas removeConstraint:[self constraintWithIdentifier:kRLMBRightMostConstraint inView:self.canvas]];
    [self addLeftConstraintsTo:pane.view after:[self.panes.lastObject view] within:self.canvas];
    [self addRightConstraintsTo:pane.view within:self.canvas];
    
    [self.panes addObject:pane];
    pane.canvasDelegate = self;
}

- (void)removePanesAfterPane:(RLMBPaneViewController *)pane
{
    while (self.panes.lastObject != pane) {
        [self removeLastPane];
    }
}
    
- (void)removeLastPane
{
    RLMBPaneViewController *paneVC = self.panes.lastObject;
    [paneVC.view removeFromSuperview];
    [self.panes removeLastObject];
    [self addRightConstraintsTo:[self.panes.lastObject view] within:self.canvas];
}

#pragma mark - Table View View Datasource - Sidebar

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView
{
    return self.objectClasses.count + 1;
}

#pragma mark - Table View Delegate - Sidebar

- (BOOL)tableView:(NSTableView *)tableView isGroupRow:(NSInteger)row
{
    return row == 0;
}

- (NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row
{
    if (row == 0) {
        NSTableCellView *cellView = [tableView makeViewWithIdentifier:@"SidebarHeaderCell" owner:self];
        NSString *fileName = [[self.realm.path pathComponents] lastObject];
        cellView.textField.stringValue = [[fileName stringByDeletingPathExtension] uppercaseString];
        
        return cellView;
    }
    
    RLMBSidebarCellView *cellView = [tableView makeViewWithIdentifier:@"SidebarClassCell" owner:self];
    RLMResults *objects = self.objectClasses[row - 1];
    cellView.textField.stringValue = objects.objectClassName;
    cellView.badge.stringValue = @(objects.count).stringValue;
//    cellView.badge.layer.cornerRadius = NSHeight(cellView.badge.frame)/2.0;
//    cellView.badge.layer.cornerRadius = 10;
//    cellView.badge.backgroundColor = [NSColor purpleColor];
    
    return cellView;
}

- (void)tableViewSelectionDidChange:(NSNotification *)notification
{
    if (notification.object == self.sidebarTableView) {
        NSInteger row = self.sidebarTableView.selectedRow - 1;
        
        if (row < self.objectClasses.count && row >= 0) {
            [self removePanesAfterPane:self.rootPane];
            
            RLMResults *objects = self.objectClasses[row];
            RLMObjectSchema *objectSchema = self.realm.schema[objects.objectClassName];
            [self.rootPane updateWithObjects:objects objectSchema:objectSchema];
        }
    }
}

#pragma mark - Navigation

- (IBAction)navigateAction:(NSSegmentedControl *)sender {
    switch (sender.selectedSegment) {
        case 0:
            [self scrollToPane:0];
            break;
        case 1:
            [self scrollToPane:self.panes.count - 1];
            break;
        default:
            break;
    }
}

- (void)scrollToPane:(NSUInteger)index
{
    NSView *pane = [self.panes[index] view];
    
    NSClipView *clipView = self.scrollView.contentView;
    NSPoint corner;
    corner.x = NSMaxX(pane.frame) + kRLMBPaneMargin - NSWidth(clipView.bounds);
    
    [NSAnimationContext beginGrouping];
    [[NSAnimationContext currentContext] setDuration:0.5];
    [clipView.animator setBoundsOrigin:corner];
    [NSAnimationContext endGrouping];
}

#pragma mark - Private Methods - Constraints

- (void)addSizeConstraintsTo:(NSView *)pane within:(NSView *)canvas
{
    pane.translatesAutoresizingMaskIntoConstraints = NO;
    
    [pane addConstraint:[NSLayoutConstraint constraintWithItem:pane
                                                     attribute:NSLayoutAttributeHeight
                                                     relatedBy:NSLayoutRelationGreaterThanOrEqual
                                                        toItem:nil
                                                     attribute:NSLayoutAttributeNotAnAttribute
                                                    multiplier:1
                                                      constant:200]];
    
    [pane addConstraint:[NSLayoutConstraint constraintWithItem:pane
                                                     attribute:NSLayoutAttributeWidth
                                                     relatedBy:NSLayoutRelationEqual
                                                        toItem:nil
                                                     attribute:NSLayoutAttributeNotAnAttribute
                                                    multiplier:1
                                                      constant:300]];
    
    [canvas addConstraint:[NSLayoutConstraint constraintWithItem:pane
                                                       attribute:NSLayoutAttributeTop
                                                       relatedBy:NSLayoutRelationEqual
                                                          toItem:canvas
                                                       attribute:NSLayoutAttributeTop
                                                      multiplier:1
                                                        constant:kRLMBPaneMargin]];
    
    [canvas addConstraint:[NSLayoutConstraint constraintWithItem:canvas
                                                       attribute:NSLayoutAttributeBottom
                                                       relatedBy:NSLayoutRelationEqual
                                                          toItem:pane
                                                       attribute:NSLayoutAttributeBottom
                                                      multiplier:1
                                                        constant:kRLMBPaneMargin]];
}

- (void)addLeftConstraintsTo:(NSView *)pane after:(NSView *)previousPane within:(NSView *)canvas
{
    if (previousPane) {
        [canvas addConstraint:[NSLayoutConstraint constraintWithItem:pane
                                                           attribute:NSLayoutAttributeLeft
                                                           relatedBy:NSLayoutRelationEqual
                                                              toItem:previousPane
                                                           attribute:NSLayoutAttributeRight
                                                          multiplier:1
                                                            constant:kRLMBPaneMargin]];
    }
    else {
        [canvas addConstraint:[NSLayoutConstraint constraintWithItem:pane
                                                           attribute:NSLayoutAttributeLeft
                                                           relatedBy:NSLayoutRelationEqual
                                                              toItem:canvas
                                                           attribute:NSLayoutAttributeLeft
                                                          multiplier:1
                                                            constant:kRLMBPaneMargin]];
    }
}

- (void)addRightConstraintsTo:(NSView *)pane within:(NSView *)canvas
{
    NSLayoutConstraint *rightConstraint = [NSLayoutConstraint constraintWithItem:canvas
                                                                       attribute:NSLayoutAttributeRight
                                                                       relatedBy:NSLayoutRelationEqual
                                                                          toItem:pane
                                                                       attribute:NSLayoutAttributeRight
                                                                      multiplier:1
                                                                        constant:kRLMBPaneMargin];
    rightConstraint.identifier = kRLMBRightMostConstraint;
    [canvas addConstraint:rightConstraint];
}

- (NSLayoutConstraint *)constraintWithIdentifier:(NSString *)identifier inView:(NSView *)view
{
    for (NSLayoutConstraint *constraint in view.constraints) {
        if ([constraint.identifier isEqualToString:identifier]) {
            return constraint;
        }
    }
    return nil;
}

#pragma mark - Private methods - Property Getters

- (RLMBRootPaneViewController *)rootPane
{
    if (self.panes.count == 0) {
        [self addPane:[[RLMBRootPaneViewController alloc] initWithNibName:@"RLMBPaneViewController" bundle:nil]];
    }
    
    return self.panes.firstObject;
}

@end
