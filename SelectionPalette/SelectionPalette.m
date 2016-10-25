//
//  SelectionPalette.m
//  SelectionPalette
//
//  Created by Daniel Gamage on 9/27/16.
//  Copyright © 2016 Daniel Gamage. All rights reserved.
//

#import "SelectionPalette.h"
#import <GlyphsCore/GSFont.h>
#import <GlyphsCore/GSFontMaster.h>
#import <GlyphsCore/GSGlyph.h>
#import <GlyphsCore/GSLayer.h>
#import <GlyphsCore/GSPath.h>
#import <GlyphsCore/GSElement.h>
#import <GlyphsCore/GSNode.h>
#import <GlyphsCore/GSWindowControllerProtocol.h>

@implementation SelectionPalette

@synthesize windowController;

- (id) init {
    self = [super init];
    [NSBundle loadNibNamed:@"SelectionPaletteView" owner:self];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(update:) name:@"GSUpdateInterface" object:nil];
    [self addMenuItems];
    return self;
}

- (NSUInteger) interfaceVersion {
    // Distinguishes the API verison the plugin was built for. Return 1.
    return 1;
}

- (NSString*) title {
    // Return the name of the tool as it will appear in the menu.
    return @"Select by Type";
}

- (void)update:(id)sender {
    layer = [windowController activeLayer];
}

- (void)addMenuItems {
	static SelectionPalette* MenuHandler = nil;
	if (!MenuHandler) {
		MenuHandler = self;
		NSApplication *app = [NSApplication sharedApplication];
		NSMenu *editMenu = [[[app mainMenu] itemAtIndex:2] submenu];

		// index + 1 so items are inserted AFTER the other selection items
		NSInteger startingIndex = [editMenu indexOfItemWithTitle:@"Invert Selection"] + 1;

		NSMenuItem *continueItem = [[NSMenuItem alloc] initWithTitle:@"Continue Selection" action:@selector(continueSelection) keyEquivalent:@"}"];
		NSMenuItem *undoItem     = [[NSMenuItem alloc] initWithTitle:@"Undo Selection"     action:@selector(undoSelection)     keyEquivalent:@"{"];
		NSMenuItem *growItem     = [[NSMenuItem alloc] initWithTitle:@"Grow Selection"     action:@selector(growSelection)     keyEquivalent:@"+"];
		NSMenuItem *shrinkItem   = [[NSMenuItem alloc] initWithTitle:@"Shrink Selection"   action:@selector(shrinkSelection)   keyEquivalent:@"-"];

		NSArray *menuItems = [[NSMutableArray alloc] initWithObjects:continueItem, undoItem, growItem, shrinkItem, nil];

		// reverse object order so that menu items get inserted atIndex in the desired order
		for (NSMenuItem *item in [menuItems reverseObjectEnumerator]) {
			[item setKeyEquivalentModifierMask: NSEventModifierFlagCommand | NSEventModifierFlagOption];
			[item setTarget:self];
			[editMenu insertItem:item atIndex:startingIndex];
		}

		// add separator at the top of the list
		[editMenu insertItem:[NSMenuItem separatorItem] atIndex:startingIndex];
	}
}

- (GSNode*) getSibling:(GSNode*)node next:(bool)next {
    GSPath *path = node.parent;
    NSUInteger index = [path indexOfNode:node];
    NSUInteger length = [path.nodes count];
    NSUInteger siblingIndex;

    if (next == YES) {
        // if last node
        siblingIndex = (index == length - 1) ? 0 : index + 1;
    } else {
        // if first node
        siblingIndex = (index == 0) ? length - 1 : index - 1;
    }

    GSNode *nextNode = [path nodeAtIndex:siblingIndex];
    return nextNode;
}

- (GSNode*) prevNode:(GSNode*)node {
    return [self getSibling:node next:NO];
}

- (GSNode*) nextNode:(GSNode*)node {
    return [self getSibling:node next:YES];
}

- (bool) isSelected:(GSNode*)node {
    return ([layer.selection containsObject:node]);
}

- (void) growSelection {
    NSMutableArray *nodesToSelect = [[NSMutableArray alloc] init];

    // Get nodes on outside edges of selection
    for (GSPath *path in layer.paths) {
        for (GSNode *node in path.nodes) {
            if (![self isSelected:node]) {
                if ([self isSelected:[self nextNode:node]] || [self isSelected:[self prevNode:node]]) {
                    [nodesToSelect addObject:node];
                }
            }
        }
    }
    // Select them
    for (GSNode *node in nodesToSelect) {
        [layer addSelection:node];
    }

}

- (void) shrinkSelection {
    NSMutableArray *nodesToDeselect = [[NSMutableArray alloc] init];

    // Get nodes on inside edges of selection
    for (GSPath *path in layer.paths) {
        for (GSNode *node in path.nodes) {
            if ([self isSelected:node]) {
                if (![self isSelected:[self nextNode:node]] || ![self isSelected:[self prevNode:node]]) {
                    [nodesToDeselect addObject:node];
                }
            }
        }
    }

    // Deselect them
    for (GSNode *node in nodesToDeselect) {
        [layer removeObjectFromSelection:node];
    }
}

- (void) continueSelection {
    // need a pattern from at least two nodes
    if ([layer.selection count] >= 2) {
        GSNode *lastNode = layer.selection[[layer.selection count] - 1];
        GSNode *originNode = layer.selection[[layer.selection count] - 2];
        // if nodes aren't on the same path, can't calculate a pattern
        if (lastNode.parent == originNode.parent) {
            GSPath *path = originNode.parent;
            NSUInteger lastNodeIndex = [path indexOfNode:lastNode];
            NSUInteger originNodeIndex = [path indexOfNode:originNode];
            NSUInteger rhythm;

            // Get difference of two nodes
            if (lastNodeIndex > originNodeIndex) {
                // normal diff
                rhythm = lastNodeIndex - originNodeIndex;
            } else {
                // crossing bounds of path
                rhythm = abs(originNodeIndex - [path.nodes count]) + lastNodeIndex;
            }

            // Move to node with rhythm
            GSNode *nodeToSelect = lastNode;
            int i = 0;
            while (i < rhythm) {
                nodeToSelect = [self nextNode:nodeToSelect];
                i += 1;
            }

            // Select it
            [layer addSelection:nodeToSelect];
        }
    }
}

- (void) performSelectionOnArray:(NSMutableArray *)selectionArray andOperation:(SelectionOperationType)operation {
    if (operation == ADD) {
        [[self layer] addObjectsFromArrayToSelection:selectionArray];
    } else if (operation == SUBTRACT) {
        [[self layer] removeObjectsFromSelection:selectionArray];
    } else if (operation == INTERSECT) {
        NSMutableArray *elementsToDeselect = [[NSMutableArray alloc] init];
        for (GSElement *element in [self layer].selection) {
            if (![selectionArray containsObject:element]) {
                [elementsToDeselect addObject:element];
            }
        }
        [[self layer] removeObjectsFromSelection:elementsToDeselect];
    }
}

- (void) selectAnchorsWithOperation:(SelectionOperationType)operation {
    NSMutableArray *selectionArray = [[NSMutableArray alloc] init];

    for (NSString *key in [self layer].anchors) {
        GSAnchor *anchor = [[self layer].anchors objectForKey:key];
        [selectionArray addObject:anchor];
    }

    [self performSelectionOnArray:selectionArray andOperation:operation];
}

- (void) selectComponentsWithOperation:(SelectionOperationType)operation {
    NSMutableArray *selectionArray = [[NSMutableArray alloc] init];

    for (GSElement *component in [self layer].components) {
        [selectionArray addObject:component];
    }

    [self performSelectionOnArray:selectionArray andOperation:operation];
}

- (void) selectNodesByType:(GSNodeType)type andSmooth:(GSNodeType)connection withOperation:(SelectionOperationType)operation {
    NSMutableArray *selectionArray = [[NSMutableArray alloc] init];

    for (GSPath *path in [self layer].paths){
        for (GSNode *node in path.nodes) {
            NSMutableArray *conditions = [[NSMutableArray alloc] init];

            // if type is set
            if (type) {
                // when looking for sharp curves, add sharp lines that neighbor offcurves
                if (type == CURVE && node.type == LINE && node.connection == SHARP && ([self nextNode:node].type == OFFCURVE || [self nextNode:node].type == OFFCURVE)) {
                    [conditions addObject:[NSNumber numberWithBool:YES]];
                } else {
                    [conditions addObject:[NSNumber numberWithBool:(node.type == type)]];
                }
            }
            // if connection is set
            if (connection == SHARP || connection == SMOOTH) {
                [conditions addObject:[NSNumber numberWithBool:(node.connection == connection)]];
            }

            // if all conditions pass...
            if (![conditions containsObject:@(0)]) {
                [selectionArray addObject:node];
                // if looking for lines, select prevNode as well (unless it's OFFCURVE)
                if (type == LINE && node.type == LINE) {
                    [selectionArray addObject:[self prevNode:node]];
                }
                // if looking for lines, add next (non-offcurve) node
                if (type == LINE && [self nextNode:node].type != OFFCURVE) {
                    [selectionArray addObject:[self nextNode:node]];
                }
            }
        }
    }

    [self performSelectionOnArray:selectionArray andOperation:operation];
}

- (void) undoSelection {
    [[self layer] removeObjectFromSelection:[[self layer].selection lastObject]];
}

- (IBAction) selectSmoothCurves:(id)sender {
    SelectionOperationType operation = [sender selectedSegment];
    // should select both line and curve nodes with smooth connections
    [self selectNodesByType:0 andSmooth:SMOOTH withOperation:operation];
}
- (IBAction) selectSharpCurves:(id)sender {
    SelectionOperationType operation = [sender selectedSegment];
    [self selectNodesByType:CURVE andSmooth:SHARP withOperation:operation];
}
- (IBAction) selectLines:(id)sender {
    SelectionOperationType operation = [sender selectedSegment];
    [self selectNodesByType:LINE andSmooth:0 withOperation:operation];
}
- (IBAction) selectHandles:(id)sender {
    SelectionOperationType operation = [sender selectedSegment];
    [self selectNodesByType:OFFCURVE andSmooth:0 withOperation:operation];
}
- (IBAction) selectAnchors:(id)sender {
    SelectionOperationType operation = [sender selectedSegment];
    [self selectAnchorsWithOperation:operation];
}
- (IBAction) selectComponents:(id)sender {
    SelectionOperationType operation = [sender selectedSegment];
    [self selectComponentsWithOperation:operation];
}

- (NSInteger) maxHeight {
    return 265;
}
- (NSInteger) minHeight {
    return 125;
}
- (NSUInteger) currentHeight {
    return [[NSUserDefaults standardUserDefaults] integerForKey:@"SelectionPaletteCurrentHeight"];
}
@end
