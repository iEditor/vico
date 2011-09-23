#import "ExTextField.h"
#import "ViThemeStore.h"
#import "ViTextView.h"
#import "ExParser.h"
#include "logging.h"

@interface NSObject (private)
- (void)textField:(ExTextField *)textField executeExCommand:(NSString *)exCommand;
@end

@implementation ExTextField

- (void)awakeFromNib
{
	NSUserDefaults *defs = [NSUserDefaults standardUserDefaults];
	NSArray *exhistory = [defs arrayForKey:@"exhistory"];
	if (exhistory)
		_history = [exhistory mutableCopy];
	else
		_history = [[NSMutableArray alloc] init];
	DEBUG(@"loaded %lu lines from history", [_history count]);
}

- (void)dealloc
{
	[_history release];
	[_current release];
	[super dealloc];
}

- (void)addToHistory:(NSString *)line
{
	/* Add the command to the history. */
	NSUInteger i = [_history indexOfObject:line];
	if (i != NSNotFound)
		[_history removeObjectAtIndex:i];
	[_history insertObject:line atIndex:0];
	while ([_history count] > 100)
		[_history removeLastObject];

	DEBUG(@"history = %@", _history);
	NSUserDefaults *defs = [NSUserDefaults standardUserDefaults];
	[defs setObject:_history forKey:@"exhistory"];
}

- (BOOL)becomeFirstResponder
{
	ViTextView *editor = (ViTextView *)[[self window] fieldEditor:YES forObject:self];
	DEBUG(@"using field editor %@", editor);

	[_current release];
	_current = nil;
	_historyIndex = -1;

	[editor setInsertMode:nil];
	[editor setCaret:0];

	_running = YES;
	return [super becomeFirstResponder];
}

- (BOOL)navigateHistory:(BOOL)upwards prefix:(NSString *)prefix
{
	if (_historyIndex == -1) {
		[_current release];
		_current = [[self stringValue] copy];
	}

	ViTextView *editor = (ViTextView *)[self currentEditor];

	int i = _historyIndex;
	DEBUG(@"history index = %i, count = %lu, prefix = %@",
	    _historyIndex, [_history count], prefix);
	while (upwards ? i + 1 < [_history count] : i > 0) {
		i += (upwards ? +1 : -1);
		NSString *item = [_history objectAtIndex:i];
		DEBUG(@"got item %@", item);
		if ([prefix length] == 0 || [[item lowercaseString] hasPrefix:prefix]) {
			DEBUG(@"insert item %@", item);
			// [self setStringValue:item];
			[editor setString:item];
			[editor setInsertMode:nil];
			_historyIndex = i;
			return YES;
		}
	}

	if (!upwards && i == 0) {
		// [self setStringValue:_current];
		[editor setString:_current];
		[editor setInsertMode:nil];
		_historyIndex = -1;
		return YES;
	}

	return NO;
}

- (BOOL)prev_history_ignoring_prefix:(ViCommand *)command
{
	return [self navigateHistory:YES prefix:nil];
}

- (BOOL)prev_history:(ViCommand *)command
{
	NSRange sel = [[self currentEditor] selectedRange];
	NSString *prefix = [[[self stringValue] substringToIndex:sel.location] lowercaseString];
	return [self navigateHistory:YES prefix:prefix];
}

- (BOOL)next_history_ignoring_prefix:(ViCommand *)command
{
	return [self navigateHistory:NO prefix:nil];
}

- (BOOL)next_history:(ViCommand *)command
{
	NSRange sel = [[self currentEditor] selectedRange];
	NSString *prefix = [[[self stringValue] substringToIndex:sel.location] lowercaseString];
	return [self navigateHistory:NO prefix:prefix];
}

- (BOOL)ex_cancel:(ViCommand *)command
{
	_running = NO;
	if ([[self delegate] respondsToSelector:@selector(textField:executeExCommand:)])
		[(NSObject *)[self delegate] textField:self executeExCommand:nil];
	return YES;
}

- (BOOL)ex_execute:(ViCommand *)command
{
	NSString *exCommand = [self stringValue];
	[self addToHistory:exCommand];
	_running = NO;
	if ([[self delegate] respondsToSelector:@selector(textField:executeExCommand:)])
		[(NSObject *)[self delegate] textField:self executeExCommand:exCommand];
	return YES;
}

- (BOOL)ex_complete:(ViCommand *)command
{
	ViTextView *editor = (ViTextView *)[[self window] fieldEditor:YES forObject:self];

	id<ViCompletionProvider> provider = nil;
	NSRange range;
	NSError *error = nil;
	[[ExParser sharedParser] parse:[self stringValue]
				 caret:[editor caret]
			    completion:&provider
				 range:&range
				 error:&error];

	DEBUG(@"completion provider is %@", provider);
	if (provider == nil)
		return NO;

	DEBUG(@"completion range is %@", NSStringFromRange(range));
	NSString *word = [[[editor textStorage] string] substringWithRange:range];
	DEBUG(@"completing word [%@]", word);

	return [editor presentCompletionsOf:word
			       fromProvider:provider
				  fromRange:range
				    options:command.mapping.parameter];
}

- (void)textDidEndEditing:(NSNotification *)aNotification
{
	if (_running)
		[self ex_cancel:nil];
	else
		[super textDidEndEditing:aNotification];
}

@end
