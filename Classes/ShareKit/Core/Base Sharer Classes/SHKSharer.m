    //
//  SHKSharer.m
//  ShareKit
//
//  Created by Nathan Weiner on 6/8/10.

//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in
//  all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
//  THE SOFTWARE.
//
//

#import "SHKSharer.h"
#import "SHKActivityIndicator.h"

@implementation SHKSharer

@synthesize shareDelegate;
@synthesize item, pendingForm, request;
@synthesize lastError;
@synthesize quiet, shareAfterAuth;

- (void)dealloc
{
	[item release];
	[shareDelegate release];
	[pendingForm release];
	[request release];
	[lastError release];
	
	[super dealloc];
}


#pragma mark -
#pragma mark Configuration : Service Defination

// Each service should subclass these and return YES/NO to indicate what type of sharing they support.
// Superclass defaults to NO so that subclasses only need to add methods for types they support

+ (NSString *)sharerTitle
{
	return @"";
}

- (NSString *)sharerTitle
{
	return [[self class] sharerTitle];
}

+ (NSString *)sharerId
{
	return NSStringFromClass([self class]);
}

- (NSString *)sharerId
{
	return [[self class] sharerId];	
}

+ (BOOL)canShareText
{
	return NO;
}

+ (BOOL)canShareURL
{
	return NO;
}

+ (BOOL)canShareImage
{
	return NO;
}

+ (BOOL)canShareFile
{
	return NO;
}

+ (BOOL)shareRequiresInternetConnection
{
	return YES;
}

+ (BOOL)canShareOffline
{
	return YES;
}

+ (BOOL)requiresAuthentication
{
	return YES;
}

+ (BOOL)canShareType:(SHKShareType)type
{
	switch (type) 
	{
		case SHKShareTypeURL:
			return [self canShareURL];
			break;
			
		case SHKShareTypeImage:
			return [self canShareImage];
			break;
			
		case SHKShareTypeText:
			return [self canShareText];
			break;
			
		case SHKShareTypeFile:
			return [self canShareFile];
			break;
	}
	return NO;
}

+ (BOOL)canAutoShare
{
	return YES;
}



#pragma mark -
#pragma mark Configuration : Dynamic Enable

// Allows a subclass to programically disable/enable services depending on the current environment

+ (BOOL)canShare
{
	return YES;
}

- (BOOL)shouldAutoShare
{	
	return [[NSUserDefaults standardUserDefaults] boolForKey:[NSString stringWithFormat:@"%@_shouldAutoShare", [self sharerId]]];
}


#pragma mark -
#pragma mark Initialization

- (id)init
{
	if (self = [super initWithNibName:nil bundle:nil])
	{
		self.shareDelegate = self;
		self.item = [[[SHKItem alloc] init] autorelease];
	}
	return self;
}


#pragma mark -
#pragma mark Share Item Loading Convenience Methods

+ (id)shareItem:(SHKItem *)i
{
	[SHK pushOnFavorites:[self sharerId] forType:i.shareType];
	
	switch (i.shareType) 
	{
		case SHKShareTypeURL:
			return [self shareURL:i.URL title:i.title];
			break;
			
		case SHKShareTypeImage:
			return [self shareImage:i.image title:i.title];
			break;
			
		case SHKShareTypeText:
			return [self shareText:i.text];
			break;
			
		case SHKShareTypeFile:
			return [self shareFile:i.data filename:i.filename mimeType:i.mimeType title:i.title];
			break;
	}
	
	return nil;
}

+ (id)shareURL:(NSURL *)url
{
	return [self shareURL:url title:nil];
}

+ (id)shareURL:(NSURL *)url title:(NSString *)title
{
	// Create controller and set share options
	SHKSharer *controller = [[self alloc] init];
	controller.item.shareType = SHKShareTypeURL;
	controller.item.URL = url;
	controller.item.title = title;

	// share and/or show UI
	[controller share];

	return [controller autorelease];
}

+ (id)shareImage:(UIImage *)image title:(NSString *)title
{
	// Create controller and set share options
	SHKSharer *controller = [[self alloc] init];
	controller.item.shareType = SHKShareTypeImage;
	controller.item.image = image;
	controller.item.title = title;
	
	// share and/or show UI
	[controller share];
	
	return [controller autorelease];
}

+ (id)shareText:(NSString *)text
{
	// Create controller and set share options
	SHKSharer *controller = [[self alloc] init];
	controller.item.shareType = SHKShareTypeText;
	controller.item.text = text;
	
	// share and/or show UI
	[controller share];
	
	return [controller autorelease];
}

+ (id)shareFile:(NSData *)file filename:(NSString *)filename mimeType:(NSString *)mimeType title:(NSString *)title
{
	// Create controller and set share options
	SHKSharer *controller = [[self alloc] init];
	controller.item.shareType = SHKShareTypeFile;
	controller.item.data = file;
	controller.item.filename = filename;
	controller.item.mimeType = mimeType;
	controller.item.title = title;
	
	// share and/or show UI
	[controller share];
	
	return [controller autorelease];
}


#pragma mark -
#pragma mark Commit Share

- (void)share
{
	// isAuthorized - If service requires login and details have not been saved, present login dialog	
	if (![self authorize])
		self.shareAfterAuth = YES;
	
	// A. First check if auto share is set	
	// B. If it is, try to send
	// If either A or B fail, display the UI
	else if (![self shouldAutoShare] || ![self tryToSend])
		[self show];
}


#pragma mark -
#pragma mark Authentication

- (BOOL)isAuthorized
{	
	if (![[self class] requiresAuthentication])
		return YES;
	
	// Checks to make sure we just have at least one variable from the authorization form
	// If the send request fails it'll reprompt the user for their new login anyway
	
	NSString *sharerId = [self sharerId];
	NSArray *fields = [self authorizationFormFields];
	for (SHKFormFieldSettings *field in fields)
	{
		if ([SHK getAuthValueForKey:field.key forSharer:sharerId] != nil)
			return YES;
	}
	
	return NO;
}

- (BOOL)authorize
{
	if ([self isAuthorized])
		return YES;
	
	else 
		[self promptAuthorization];
	
	return NO;
}

- (void)promptAuthorization
{
	if ([[self class] shareRequiresInternetConnection] && ![SHK connected])
	{
		if (!quiet)
		{
			[[[[UIAlertView alloc] initWithTitle:@"Offline"
										 message:[NSString stringWithFormat:@"You must be online to login to %@", [self sharerTitle]]
										delegate:nil
							   cancelButtonTitle:@"Close"
							   otherButtonTitles:nil] autorelease] show];
		}
		return;
	}
	
	[self authorizationFormShow];
}

- (NSString *)getAuthValueForKey:(NSString *)key
{
	return [SHK getAuthValueForKey:key forSharer:[self sharerId]];
}

- (void)setShouldAutoShare:(BOOL)b
{
	return [[NSUserDefaults standardUserDefaults] setBool:b forKey:[NSString stringWithFormat:@"%@_shouldAutoShare", [self sharerId]]];
}

#pragma mark Authorization Form

- (void)authorizationFormShow
{	
	// Create the form
	SHKCustomFormController *form = [[SHKCustomFormController alloc] initWithStyle:UITableViewStyleGrouped title:@"Login" rightButtonTitle:@"Login"];
	[form addSection:[self authorizationFormFields] header:nil footer:[self authorizationFormCaption]];
	form.delegate = self;
	form.validateSelector = @selector(authorizationFormValidate:);
	form.saveSelector = @selector(authorizationFormSave:);
	form.autoSelect = YES;
	
	[[SHK currentHelper] showViewController:form];
	[form release];
}

- (void)authorizationFormValidate:(SHKFormController *)form
{
	/*
	 
	Services should subclass this.
	You can get a dictionary of the field values from [form formValues]
	 
	--
	 
	You should perform one of the following actions:
	 
	1.	Display an error - If the user input was incorrect, display an error to the user and tell them what to do to fix it
	 
	2.	Save the form - If everything is correct call [form saveForm]
	 
	3.	Display a pending indicator - If you need to authorize the details on the server, display an activity indicator with [form displayActivity:@"DESCRIPTION OF WHAT YOU ARE DOING"]
		After your process completes be sure to perform either 1 or 2 above.
	 	 
	*/
}

- (void)authorizationFormSave:(SHKFormController *)form
{		
	// -- Save values 
	NSDictionary *formValues = [form formValues];
	
	NSString *value;
	NSString *sharerId = [self sharerId];
	NSArray *fields = [[[form sections] objectAtIndex:0] objectForKey:@"rows"];
	for(SHKFormFieldSettings *field in fields)
	{
		value = [formValues objectForKey:field.key];
		[SHK setAuthValue:value forKey:field.key forSharer:sharerId];
	}	
		
	// -- Try to share again
	[self share];
}

- (NSArray *)authorizationFormFields
{
	return [NSArray arrayWithObjects:
			[SHKFormFieldSettings label:@"Username" key:@"username" type:SHKFormFieldTypeText start:nil],
			[SHKFormFieldSettings label:@"Password" key:@"password" type:SHKFormFieldTypePassword start:nil],			
			nil];
}

- (NSString *)authorizationFormCaption
{
	return nil;
}




#pragma mark -
#pragma mark UI Implementation

- (void)show
{
	NSArray *shareFormFields = [self shareFormFieldsForType:item.shareType];
	
	if (shareFormFields == nil)
		[self tryToSend];
	
	else 
	{	
		SHKCustomFormController *rootView = [[SHKCustomFormController alloc] initWithStyle:UITableViewStyleGrouped 
																		 title:nil
															  rightButtonTitle:[NSString stringWithFormat:@"Send to %@", [[self class] sharerTitle]]
									   ];
		[rootView addSection:[self shareFormFieldsForType:item.shareType] header:nil footer:item.URL!=nil?item.URL.absoluteString:nil];
		
		if ([[self class] canAutoShare])
		{
			[rootView addSection:
			[NSArray arrayWithObject:
			[SHKFormFieldSettings label:@"Auto Share" key:@"autoShare" type:SHKFormFieldTypeSwitch start:([self shouldAutoShare]?SHKFormFieldSwitchOn:SHKFormFieldSwitchOff)]
			 ]
						header:nil
						footer:@"Enable auto share to skip this step in the future."];
		}
		
		rootView.delegate = self;
		rootView.validateSelector = @selector(shareFormValidate:);
		rootView.saveSelector = @selector(shareFormSave:);
		
		[self pushViewController:rootView animated:NO];
		
		[[SHK currentHelper] showViewController:self];
	}
}




#pragma mark -
#pragma mark Share Form

- (NSArray *)shareFormFieldsForType:(SHKShareType)type
{
	if (type == SHKShareTypeURL)
		return [NSArray arrayWithObjects:
				[SHKFormFieldSettings label:@"Title" key:@"title" type:SHKFormFieldTypeText start:item.title],
				nil];
	
	return nil;
}

- (void)shareFormValidate:(SHKCustomFormController *)form
{	
	/*
	 
	 Services should subclass this if they need to validate any data before sending.
	 You can get a dictionary of the field values from [form formValues]
	 
	 --
	 
	 You should perform one of the following actions:
	 
	 1.	Display an error - If the user input was incorrect, display an error to the user and tell them what to do to fix it
	 
	 2.	Save the form - If everything is correct call [form save]
	 
	 3.	Display a pending indicator - If you need to authorize the details on the server, display an activity indicator with [form displayActivity:@"DESCRIPTION OF WHAT YOU ARE DOING"]
	 After your process completes be sure to perform either 1 or 2 above.
	 
	*/
	
	
	// default does no checking and proceeds to share
	[form saveForm];
}

- (void)shareFormSave:(SHKFormController *)form
{		
	// Update item with new values from form
	NSDictionary *formValues = [form formValues];
	for(NSString *key in formValues)
	{
		if ([key isEqualToString:@"title"])
			item.title = [formValues objectForKey:key];
		
		else if ([key isEqualToString:@"text"])
			item.text = [formValues objectForKey:key];
		
		else if ([key isEqualToString:@"tags"])
			item.tags = [formValues objectForKey:key];
		
		else
			[item setCustomValue:[formValues objectForKey:key] forKey:key];
	}
	
	// Update shouldAutoShare
	NSDictionary *advancedOptions = [form formValuesForSection:1];
	if ([advancedOptions objectForKey:@"autoShare"] != nil)
		[self setShouldAutoShare:[[advancedOptions objectForKey:@"autoShare"] isEqualToString:SHKFormFieldSwitchOn]];	
	
	// Send the share
	[self tryToSend];
}


#pragma mark -
#pragma mark API Implementation

- (BOOL)validateItem
{
	switch (item.shareType) 
	{
		case SHKShareTypeURL:
			return (item.URL != nil);
			break;			
			
		case SHKShareTypeImage:
			return (item.image != nil);
			break;			
			
		case SHKShareTypeText:
			return (item.text != nil);
			break;
	}
	
	return NO;
}

- (BOOL)tryToSend
{
	if (![[self class] shareRequiresInternetConnection] || [SHK connected])
		return [self send];
	
	else if ([[self class] canShareOffline])
		return [SHK addToOfflineQueue:item forSharer:[self sharerId]];
	
	else if (!quiet)
	{
		[[[[UIAlertView alloc] initWithTitle:@"Offline"
									 message:[NSString stringWithFormat:@"You must be online in order to share with %@", [self sharerTitle]]
									delegate:nil
						   cancelButtonTitle:@"Close"
						   otherButtonTitles:nil] autorelease] show];
		
		return YES;
	}
	
	
	return NO;
}

- (BOOL)send
{	
	// Does not actually send anything.
	// Your subclass should implement the sending logic.
	// There is no reason to call [super send] in your subclass
	
	// You should never call [XXX send] directly, you should use [XXX tryToSend].  TryToSend will perform an online check before trying to send.
	return NO;
}

#pragma mark -
#pragma mark Default UI Updating

// These are used if you do not provide your own custom UI and delegate


- (void)sharerStartedSending:(SHKSharer *)sharer
{
	if (!quiet)
		[[SHKActivityIndicator currentIndicator] displayActivity:[NSString stringWithFormat:@"Saving to %@", [[self class] sharerTitle]]];
}

- (void)sharerFinishedSending:(SHKSharer *)sharer
{
	if (!quiet)
		[[SHKActivityIndicator currentIndicator] displayCompleted:@"Saved!"];
}

- (void)sharer:(SHKSharer *)sharer failedWithError:(NSError *)error shouldRelogin:(BOOL)shouldRelogin
{
	if (!quiet)
	{
		[[SHKActivityIndicator currentIndicator] hide];
		
		[[[[UIAlertView alloc] initWithTitle:@"Error"
									 message:sharer.lastError!=nil?[sharer.lastError localizedDescription]:@"There was an error while sharing"
									delegate:nil
						   cancelButtonTitle:@"Close"
						   otherButtonTitles:nil] autorelease] show];
		
		if (shouldRelogin)
			[self promptAuthorization];
	}
}

- (void)sharerCancelledSending:(SHKSharer *)sharer
{
	
}



#pragma mark -

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation 
{
    return YES;
}


#pragma mark -
#pragma mark Delegate Notifications

- (void)sendDidStart
{		
	if ([shareDelegate respondsToSelector:@selector(sharerStartedSending:)])
		[shareDelegate performSelector:@selector(sharerStartedSending:) withObject:self];
}

- (void)sendDidFinish
{	
	if ([shareDelegate respondsToSelector:@selector(sharerFinishedSending:)])
		[shareDelegate performSelector:@selector(sharerFinishedSending:) withObject:self];
}

- (void)sendDidFailShouldRelogin
{
	[self sendDidFailWithError:[SHK error:@"Could not authenticate you.  Please relogin."] shouldRelogin:YES];
}

- (void)sendDidFailWithError:(NSError *)error
{
	[self sendDidFailWithError:error shouldRelogin:NO];	
}

- (void)sendDidFailWithError:(NSError *)error shouldRelogin:(BOOL)shouldRelogin
{
	self.lastError = error;
		
	if ([shareDelegate respondsToSelector:@selector(sharer:failedWithError:shouldRelogin:)])
		[(SHKSharer *)shareDelegate sharer:self failedWithError:error shouldRelogin:shouldRelogin];
}

- (void)sendDidCancel
{
	if ([shareDelegate respondsToSelector:@selector(sharerCancelledSending:)])
		[shareDelegate performSelector:@selector(sharerCancelledSending:) withObject:self];	
}


@end
