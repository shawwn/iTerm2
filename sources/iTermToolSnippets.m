//
//  iTermToolSnippets.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 8/14/20.
//

#import "iTermToolSnippets.h"

#import "DebugLogging.h"
#import "iTermActionsModel.h"
#import "iTermEditSnippetWindowController.h"
#import "iTermSnippetsModel.h"
#import "iTermTuple.h"
#import "iTermCompetentTableRowView.h"

#import "NSArray+iTerm.h"
#import "NSFont+iTerm.h"
#import "NSImage+iTerm.h"
#import "NSIndexSet+iTerm.h"
#import "NSStringITerm.h"
#import "NSTableView+iTerm.h"
#import "NSTextField+iTerm.h"

static const CGFloat kButtonHeight = 23;
static const CGFloat kMargin = 4;
static NSString *const iTermToolSnippetsPasteboardType = @"iTermToolSnippetsPasteboardType";


@interface iTermToolSnippets() <NSDraggingDestination, NSTableViewDataSource, NSTableViewDelegate>
@end

@implementation iTermToolSnippets {
    NSScrollView *_scrollView;
    NSTableView *_tableView;

    NSButton *_applyButton;
    NSButton *_advancedPasteButton;
    NSButton *_addButton;
    NSButton *_removeButton;
    NSButton *_editButton;

    NSArray<iTermSnippet *> *_snippets;
    iTermEditSnippetWindowController *_windowController;
}

static NSButton *iTermToolSnippetsNewButton(NSString *imageName, NSString *title, id target, SEL selector, NSRect frame) {
    NSButton *button = [[NSButton alloc] initWithFrame:NSMakeRect(0, frame.size.height - kButtonHeight, frame.size.width, kButtonHeight)];
    [button setButtonType:NSButtonTypeMomentaryPushIn];
    if (imageName) {
        if (@available(macOS 10.16, *)) {
            button.image = [NSImage it_imageForSymbolName:imageName accessibilityDescription:title];
        } else {
            button.image = [NSImage imageNamed:imageName];
        }
    } else {
        button.title = title;
    }
    [button setTarget:target];
    [button setAction:selector];
    if (@available(macOS 10.16, *)) {
        button.bezelStyle = NSBezelStyleRegularSquare;
        button.bordered = NO;
        button.imageScaling = NSImageScaleProportionallyUpOrDown;
        button.imagePosition = NSImageOnly;
    } else {
        [button setBezelStyle:NSBezelStyleSmallSquare];
    }
    [button sizeToFit];
    [button setAutoresizingMask:NSViewMinYMargin];

    return button;
}

- (instancetype)initWithFrame:(NSRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        if (@available(macOS 10.16, *)) {
            _applyButton = iTermToolSnippetsNewButton(@"play", @"Send", self, @selector(apply:), frame);
            _addButton = iTermToolSnippetsNewButton(@"plus", @"Add", self, @selector(add:), frame);
            _removeButton = iTermToolSnippetsNewButton(@"minus", @"Remove", self, @selector(remove:), frame);
            _editButton = iTermToolSnippetsNewButton(@"pencil", @"Edit", self, @selector(edit:), frame);
            _advancedPasteButton = iTermToolSnippetsNewButton(@"rectangle.and.pencil.and.ellipsis", @"Open in Advanced Paste", self, @selector(openInAdvancedPaste:), frame);
            [self addSubview:_advancedPasteButton];
        } else {
            _applyButton = iTermToolSnippetsNewButton(nil, @"Send", self, @selector(apply:), frame);
            _addButton = iTermToolSnippetsNewButton(NSImageNameAddTemplate, nil, self, @selector(add:), frame);
            _removeButton = iTermToolSnippetsNewButton(NSImageNameRemoveTemplate, nil, self, @selector(remove:), frame);
            _editButton = iTermToolSnippetsNewButton(nil, @"✐", self, @selector(edit:), frame);
        }
        [self addSubview:_applyButton];
        [self addSubview:_addButton];
        [self addSubview:_removeButton];
        [self addSubview:_editButton];

        _scrollView = [[NSScrollView alloc] initWithFrame:NSMakeRect(0, 0, frame.size.width, frame.size.height - kButtonHeight - kMargin)];
        _scrollView.hasVerticalScroller = YES;
        _scrollView.hasHorizontalScroller = NO;
        if (@available(macOS 10.16, *)) {
            _scrollView.borderType = NSLineBorder;
            _scrollView.scrollerStyle = NSScrollerStyleOverlay;
        } else {
            _scrollView.borderType = NSBezelBorder;
        }
        NSSize contentSize = [_scrollView contentSize];
        [_scrollView setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
        _scrollView.drawsBackground = NO;

        _tableView = [[NSTableView alloc] initWithFrame:NSMakeRect(0, 0, contentSize.width, contentSize.height)];
#ifdef MAC_OS_X_VERSION_10_16
        if (@available(macOS 10.16, *)) {
            _tableView.style = NSTableViewStyleInset;
        }
#endif
        NSTableColumn *valueColumn = [[NSTableColumn alloc] initWithIdentifier:@"value"];
        [valueColumn setEditable:NO];
        [_tableView addTableColumn:valueColumn];

        _tableView.columnAutoresizingStyle = NSTableViewUniformColumnAutoresizingStyle;
        _tableView.headerView = nil;
        _tableView.dataSource = self;
        _tableView.delegate = self;
        _tableView.intercellSpacing = NSMakeSize(_tableView.intercellSpacing.width, 0);
        _tableView.rowHeight = 15;
        _tableView.allowsMultipleSelection = YES;
        [_tableView registerForDraggedTypes:@[ iTermToolSnippetsPasteboardType ]];

        [_tableView setDoubleAction:@selector(doubleClickOnTableView:)];
        [_tableView setAutoresizingMask:NSViewWidthSizable];

        [_scrollView setDocumentView:_tableView];
        [self addSubview:_scrollView];

        [_tableView sizeToFit];
        [_tableView sizeLastColumnToFit];

        [_tableView performSelector:@selector(scrollToEndOfDocument:) withObject:nil afterDelay:0];
        _snippets = [[[iTermSnippetsModel sharedInstance] snippets] copy];
        [_tableView reloadData];
        if (@available(macOS 10.14, *)) {
            _tableView.backgroundColor = [NSColor clearColor];
        }

        __weak __typeof(self) weakSelf = self;
        [iTermSnippetsDidChangeNotification subscribe:self
                                                block:^(iTermSnippetsDidChangeNotification * _Nonnull notification) {
            [weakSelf snippetsDidChange:notification];
        }];
        [self relayout];
        [self updateEnabled];
        [self registerForDraggedTypes:@[ NSPasteboardTypeString ]];
    }
    return self;
}

#pragma mark - ToolbeltTool

- (void)shutdown {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)resizeSubviewsWithOldSize:(NSSize)oldSize {
    [super resizeSubviewsWithOldSize:oldSize];
    [self relayout];
}

- (void)relayout {
    NSRect frame = self.frame;
    [_applyButton sizeToFit];
    [_applyButton setFrame:NSMakeRect(0, frame.size.height - kButtonHeight, _applyButton.frame.size.width, kButtonHeight)];

    [_advancedPasteButton sizeToFit];
    CGFloat margin = -1;
    if (@available(macOS 10.16, *)) {
        margin = 2;
    }
    _advancedPasteButton.frame = NSMakeRect(NSMaxX(_applyButton.frame) + margin,
                                            frame.size.height - kButtonHeight,
                                            _advancedPasteButton.frame.size.width,
                                            kButtonHeight);

    CGFloat x = frame.size.width;
    for (NSButton *button in @[ _addButton, _removeButton, _editButton]) {
        [button sizeToFit];
        CGFloat width;
        if (@available(macOS 10.16, *)) {
            width = NSWidth(button.frame);
        } else {
            width = MAX(kButtonHeight, button.frame.size.width);
        }
        x -= width + margin;
        button.frame = NSMakeRect(x,
                                  frame.size.height - kButtonHeight,
                                  width,
                                  kButtonHeight);
    }

    [_scrollView setFrame:NSMakeRect(0, 0, frame.size.width, frame.size.height - kButtonHeight - kMargin)];
    NSSize contentSize = [self contentSize];
    [_tableView setFrame:NSMakeRect(0, 0, contentSize.width, contentSize.height)];
}

- (CGFloat)minimumHeight {
    return 60;
}

#pragma mark - NSView

- (BOOL)isFlipped {
    return YES;
}

#pragma mark - Snippets

- (BOOL)optionPressed {
    return !!([[NSApp currentEvent] modifierFlags] & NSEventModifierFlagOption);
}

- (void)doubleClickOnTableView:(id)sender {
    [self applySelectedSnippets:[self optionPressed]];
}

- (void)apply:(id)sender {
    [self applySelectedSnippets:[self optionPressed]];
}

- (void)openInAdvancedPaste:(id)sender {
    [self applySelectedSnippets:YES];
}

- (void)add:(id)sender {
    _windowController = [[iTermEditSnippetWindowController alloc] initWithSnippet:nil
                                                                       completion:^(iTermSnippet * _Nullable snippet) {
        if (!snippet) {
            return;
        }
        [[iTermSnippetsModel sharedInstance] addSnippet:snippet];
    }];
    [self.window beginSheet:_windowController.window completionHandler:^(NSModalResponse returnCode) {}];
}

- (void)remove:(id)sender {
    NSArray<iTermSnippet *> *snippets = [self selectedSnippets];
    [self pushUndo];
    [[iTermSnippetsModel sharedInstance] removeSnippets:snippets];
}

- (void)edit:(id)sender {
    iTermSnippet *snippet = [[self selectedSnippets] firstObject];
    if (snippet) {
        _windowController = [[iTermEditSnippetWindowController alloc] initWithSnippet:snippet
                                                                           completion:^(iTermSnippet * _Nullable updatedSnippet) {
            if (!updatedSnippet) {
                return;
            }
            [[iTermSnippetsModel sharedInstance] replaceSnippet:snippet withSnippet:updatedSnippet];
        }];
        [self.window beginSheet:_windowController.window completionHandler:^(NSModalResponse returnCode) {}];
    }
}

- (BOOL)performKeyEquivalent:(NSEvent *)event {
    if (_tableView.window.firstResponder == _tableView && event.keyCode == kVK_Delete) {
        [self remove:nil];
        return YES;
    }
    return [super performKeyEquivalent:event];
}

#pragma mark - Private

- (void)snippetsDidChange:(iTermSnippetsDidChangeNotification *)notif {
    _snippets = [[[iTermSnippetsModel sharedInstance] snippets] copy];
    switch (notif.mutationType) {
        case iTermSnippetsDidChangeMutationTypeEdit: {
            [_tableView it_performUpdateBlock:^{
                [_tableView reloadDataForRowIndexes:[NSIndexSet indexSetWithIndex:notif.index]
                                      columnIndexes:[NSIndexSet indexSetWithIndexesInRange:NSMakeRange(0, 1)]];
            }];
            break;
        }
        case iTermSnippetsDidChangeMutationTypeDeletion: {
            [_tableView it_performUpdateBlock:^{
                [_tableView removeRowsAtIndexes:notif.indexSet
                                  withAnimation:YES];
            }];
            break;
        }
        case iTermSnippetsDidChangeMutationTypeInsertion: {
            [_tableView it_performUpdateBlock:^{
                [_tableView insertRowsAtIndexes:[NSIndexSet indexSetWithIndex:notif.index]
                                  withAnimation:YES];
            }];
            break;
        }
        case iTermSnippetsDidChangeMutationTypeMove: {
            [_tableView it_performUpdateBlock:^{
                [_tableView removeRowsAtIndexes:notif.indexSet
                                  withAnimation:YES];
                NSMutableIndexSet *insertionIndexes = [NSMutableIndexSet indexSet];
                for (NSInteger i = 0; i < notif.indexSet.count; i++) {
                    [insertionIndexes addIndex:notif.index + i];
                }
                [_tableView insertRowsAtIndexes:insertionIndexes
                                  withAnimation:YES];
            }];
            break;
        }
        case iTermSnippetsDidChangeMutationTypeFullReplacement:
            [_tableView reloadData];
            break;
    }
}

- (void)applySelectedSnippets:(BOOL)sendToAdvancedPaste {
    DLog(@"%@", [NSThread callStackSymbols]);
    for (iTermSnippet *snippet in [self selectedSnippets]) {
        DLog(@"Create action to send snippet %@", snippet);
        iTermToolWrapper *wrapper = self.toolWrapper;
        if (sendToAdvancedPaste) {
            [wrapper.delegate.delegate toolbeltOpenAdvancedPasteWithString:snippet.value
                                                                  escaping:snippet.escaping];
        } else {
            iTermAction *action = [[iTermAction alloc] initWithTitle:@"Send Snippet"
                                                              action:KEY_ACTION_SEND_SNIPPET
                                                           parameter:snippet.actionKey
                                                            escaping:snippet.escaping
                                                             version:snippet.version];
            [wrapper.delegate.delegate toolbeltApplyActionToCurrentSession:action];
        }
    }
}

- (NSArray<iTermSnippet *> *)selectedSnippets {
    DLog(@"selected row indexes are %@", _tableView.selectedRowIndexes);
    NSArray<iTermSnippet *> *snippets = [[iTermSnippetsModel sharedInstance] snippets];
    DLog(@"Snippets are:\n%@", snippets);
    return [[_tableView.selectedRowIndexes it_array] mapWithBlock:^id(NSNumber *indexNumber) {
        DLog(@"Add snippet at %@", indexNumber);
        return snippets[indexNumber.integerValue];
    }];
}

- (NSSize)contentSize {
    NSSize size = [_scrollView contentSize];
    size.height = _tableView.intrinsicContentSize.height;
    return size;
}

- (NSString *)combinedStringForRow:(NSInteger)rowIndex {
    iTermSnippet *snippet = _snippets[rowIndex];
    NSString *title = [snippet trimmedTitle:256];
    if (!title.length) {
        return [self valueStringForRow:rowIndex];
    }
    return [NSString stringWithFormat:@"%@ — %@", title, [snippet trimmedValue:256]];
}

- (NSString *)valueStringForRow:(NSInteger)rowIndex {
    return [_snippets[rowIndex] trimmedValue:40];
}

- (void)update {
    [_tableView reloadData];
    // Updating the table data causes the cursor to change into an arrow!
    [self performSelector:@selector(fixCursor) withObject:nil afterDelay:0];

    NSResponder *firstResponder = [[_tableView window] firstResponder];
    if (firstResponder != _tableView) {
        [_tableView scrollToEndOfDocument:nil];
    }
}

- (void)fixCursor {
    [self.toolWrapper.delegate.delegate toolbeltUpdateMouseCursor];
}

- (void)updateEnabled {
    const NSInteger numberOfRows = [[self selectedSnippets] count];
    _applyButton.enabled = numberOfRows > 0;
    _advancedPasteButton.enabled = numberOfRows == 1;
    _removeButton.enabled = numberOfRows > 0;
    _editButton.enabled = numberOfRows == 1;
}

#pragma mark - NSTableViewDelegate

- (NSTableRowView *)tableView:(NSTableView *)tableView rowViewForRow:(NSInteger)row {
    if (@available(macOS 10.16, *)) {
        return [[iTermBigSurTableRowView alloc] initWithFrame:NSZeroRect];
    }
    return [[iTermCompetentTableRowView alloc] initWithFrame:NSZeroRect];
}

- (NSView *)tableView:(NSTableView *)tableView
   viewForTableColumn:(NSTableColumn *)tableColumn
                  row:(NSInteger)row {
    iTermSnippet *snippet = _snippets[row];
    if ([snippet titleEqualsValueUpToLength:40]) {
        static NSString *const identifier = @"ToolSnippetValue";
        NSTextField *result = [tableView makeViewWithIdentifier:identifier owner:self];
        if (result == nil) {
            result = [NSTextField it_textFieldForTableViewWithIdentifier:identifier];
        }

        NSString *value = [self valueStringForRow:row];
        result.stringValue = value;
        result.font = [NSFont it_toolbeltFont];
        result.lineBreakMode = NSLineBreakByTruncatingTail;
        return result;
    }

    static NSString *const identifier = @"ToolSnippetCombined";
    NSTextField *result = [tableView makeViewWithIdentifier:identifier owner:self];
    if (result == nil) {
        result = [NSTextField it_textFieldForTableViewWithIdentifier:identifier];
    }

    NSString *value = [self combinedStringForRow:row];
    result.stringValue = value;
    result.lineBreakMode = NSLineBreakByTruncatingTail;
    return result;
}


- (void)tableViewSelectionDidChange:(NSNotification *)notification {
    [self updateEnabled];
}

#pragma mark - NSTableViewDataSource

- (NSInteger)numberOfRowsInTableView:(NSTableView *)aTableView {
    return _snippets.count;
}

#pragma mark Drag-Drop

- (BOOL)tableView:(NSTableView *)tableView
writeRowsWithIndexes:(NSIndexSet *)rowIndexes
     toPasteboard:(NSPasteboard*)pboard {
    [pboard declareTypes:@[ iTermToolSnippetsPasteboardType, NSPasteboardTypeString ]
                   owner:self];

    NSArray<NSNumber *> *plist = [rowIndexes.it_array mapWithBlock:^id(NSNumber *anObject) {
        return _snippets[anObject.integerValue].guid;
    }];
    [pboard setPropertyList:plist
                    forType:iTermToolSnippetsPasteboardType];
    [pboard setString:[[rowIndexes.it_array mapWithBlock:^id(NSNumber *anObject) {
        return _snippets[anObject.integerValue].value;
    }] componentsJoinedByString:@"\n"]
              forType:NSPasteboardTypeString];
    return YES;
}

- (NSDragOperation)tableView:(NSTableView *)aTableView
                validateDrop:(id<NSDraggingInfo>)info
                 proposedRow:(NSInteger)row
       proposedDropOperation:(NSTableViewDropOperation)operation {
    if ([info draggingSource] != aTableView) {
        return NSDragOperationNone;
    }

    // Add code here to validate the drop
    switch (operation) {
        case NSTableViewDropOn:
            return NSDragOperationNone;

        case NSTableViewDropAbove:
            return NSDragOperationMove;

        default:
            return NSDragOperationNone;
    }
}

- (BOOL)tableView:(NSTableView *)aTableView
       acceptDrop:(id <NSDraggingInfo>)info
              row:(NSInteger)row
    dropOperation:(NSTableViewDropOperation)operation {
    [self pushUndo];
    NSPasteboard *pboard = [info draggingPasteboard];
    NSArray<NSString *> *guids = [pboard propertyListForType:iTermToolSnippetsPasteboardType];
    [[iTermSnippetsModel sharedInstance] moveSnippetsWithGUIDs:guids
                                                       toIndex:row];
    return YES;
}

- (void)setSnippets:(NSArray<iTermSnippet *> *)snippets {
    [self pushUndo];
    [[iTermSnippetsModel sharedInstance] setSnippets:snippets];
}

- (void)pushUndo {
    [[self undoManager] registerUndoWithTarget:self
                                      selector:@selector(setSnippets:)
                                        object:_snippets];
}

#pragma mark - NSDraggingDestination

- (NSDragOperation)draggingEntered:(id <NSDraggingInfo>)sender {
    BOOL pasteOK = !![[sender draggingPasteboard] availableTypeFromArray:@[ NSPasteboardTypeString ]];
    if (!pasteOK) {
        return NSDragOperationNone;
    }
    return NSDragOperationGeneric;
}

- (BOOL)performDragOperation:(id<NSDraggingInfo>)sender {
    NSPasteboard *draggingPasteboard = [sender draggingPasteboard];
    NSArray<NSPasteboardType> *types = [draggingPasteboard types];
    if (![types containsObject:NSPasteboardTypeString]) {
        return NO;
    }
    NSString *string = [draggingPasteboard stringForType:NSPasteboardTypeString];
    if (!string.length) {
        return NO;
    }
    NSString *title = [self titleFromString:string];
    iTermSnippet *snippet = [[iTermSnippet alloc] initWithTitle:title
                                                          value:string
                                                           guid:[[NSUUID UUID] UUIDString]
                                                       escaping:iTermSendTextEscapingNone
                                                        version:[iTermSnippet currentVersion]];
    [[iTermSnippetsModel sharedInstance] addSnippet:snippet];
    return YES;
}

- (NSString *)titleFromString:(NSString *)string {
    NSArray<NSString *> *parts = [string componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]];
    return [parts objectPassingTest:^BOOL(NSString *element, NSUInteger index, BOOL *stop) {
        return [[element stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]] length] > 0;
    }] ?: @"Untitled";
}

- (BOOL)prepareForDragOperation:(id<NSDraggingInfo>)sender {
    return YES;
}

- (BOOL)wantsPeriodicDraggingUpdates {
    return YES;
}

@end
