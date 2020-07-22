#include <napi.h>
#import <Contacts/Contacts.h>

/***** HELPERS *****/

NSString *DecodeLabel(NSString *label) {
  label = [label lowercaseString];
  if (label.length < 6 || [[label substringToIndex:2] isEqualToString:@"_$!"])  {
    return label;
  }
  NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:@"<(.*)>" options:0 error:nil];
  NSRange range = [regex rangeOfFirstMatchInString:label options:0 range:NSMakeRange(0,label.length)];
  if (range.location == NSNotFound) {
    return label;
  }
  return [label substringWithRange:NSMakeRange(range.location+1,range.length-2)];
}

Napi::Object DecodeError(Napi::Env env, NSError *error) {
  Napi::Object obj = Napi::Object::New(env);
  obj.Set("code", Napi::Number::New(env, error.code));
  obj.Set("message", Napi::String::New(env, [[error localizedDescription] UTF8String]));
  return obj;
}

Napi::Array GetEmailAddresses(Napi::Env env, CNContact *cncontact) {
  NSArray <CNLabeledValue<NSString*>*> *emailAddresses = [cncontact emailAddresses];
  Napi::Array email_addresses = Napi::Array::New(env);
  int count = 0;
  for (CNLabeledValue<NSString*> *email_address in emailAddresses) {
    if (email_address.value.length > 0) {
      Napi::Object email = Napi::Object::New(env);
      email.Set("type", std::string([DecodeLabel([email_address label]) UTF8String]));
      email.Set("value", std::string([[email_address value] UTF8String]));
      email_addresses[count++] = email;
    }
  }
  return email_addresses;
}

Napi::Array GetPhoneNumbers(Napi::Env env, CNContact *cncontact) {
  NSArray <CNLabeledValue<CNPhoneNumber*>*> *phoneNumbers = [cncontact phoneNumbers];
  Napi::Array phone_numbers = Napi::Array::New(env);
  int count = 0;
  for (CNLabeledValue<CNPhoneNumber*> *cnphone in phoneNumbers) {
    if ([cnphone.value stringValue].length > 0) {
      Napi::Object phone = Napi::Object::New(env);
      phone.Set("type", std::string([DecodeLabel([cnphone label]) UTF8String]));
      phone.Set("value", std::string([[cnphone.value stringValue] UTF8String]));
      phone_numbers[count++] = phone;
    }
  }
  return phone_numbers;
}

Napi::Array GetPostalAddresses(Napi::Env env, CNContact *cncontact) {
  if ([[cncontact postalAddresses] count] < 1) {
    return Napi::Array::New(env, 0);
  }
  Napi::Object address = Napi::Object::New(env);
  CNPostalAddress *cnaddress = [[[cncontact postalAddresses] valueForKey:@"value"] objectAtIndex: 0];
  address.Set("pref", true);
  address.Set("streetAddress", [[cnaddress street] UTF8String]);
  address.Set("locality", [[cnaddress city] UTF8String]);
  address.Set("region", [[cnaddress state] UTF8String]);
  address.Set("postalCode", [[cnaddress postalCode] UTF8String]);
  address.Set("country", [[cnaddress country] UTF8String]);
  Napi::Array postal_addresses = Napi::Array::New(env, 1);
  postal_addresses[(int)0] = address;

  return postal_addresses;
}

Napi::Array GetOrganizations(Napi::Env env, CNContact *cncontact) {
  Napi::Array organizations = Napi::Array::New(env, 1);
  Napi::Object organization = Napi::Object::New(env);
  organization.Set("name", std::string([[cncontact organizationName] UTF8String]));
  organization.Set("title", std::string([[cncontact jobTitle] UTF8String]));
  organizations[(int)0] = organization;
  return organizations;
}

Napi::Object CreateContact(Napi::Env env, CNContact *cncontact) {
  Napi::Object contact = Napi::Object::New(env);

  contact.Set("id", std::string([[cncontact identifier] UTF8String]));

  Napi::Object name = Napi::Object::New(env);
  name.Set("givenName", std::string([[cncontact givenName] UTF8String]));
  name.Set("familyName", std::string([[cncontact familyName] UTF8String]));
  contact.Set("name", name);
  contact.Set("nickname", std::string([[cncontact nickname] UTF8String]));

  // organizations
  Napi::Array organizations = GetOrganizations(env, cncontact);
  contact.Set("organizations", organizations);

  // compatibility - note access no longer allowed
  contact.Set("note", "");

  // Populate postal address array
  Napi::Array postal_addresses = GetPostalAddresses(env, cncontact);
  contact.Set("addresses", postal_addresses);

  // Populate email address array
  Napi::Array email_addresses = GetEmailAddresses(env, cncontact);
  contact.Set("emails", email_addresses);

  // Populate phone number array
  Napi::Array phone_numbers = GetPhoneNumbers(env, cncontact);
  contact.Set("phoneNumbers", phone_numbers);

  if ([cncontact imageDataAvailable]) {
    contact.Set("image", std::string([[[cncontact thumbnailImageData] base64EncodedStringWithOptions:0] UTF8String]));
  }

  return contact;
}

CNAuthorizationStatus AuthStatus() {
  CNEntityType entityType = CNEntityTypeContacts;
  return [CNContactStore authorizationStatusForEntityType:entityType];
}

NSArray* GetContactKeys() {
  NSArray *keys = @[
    CNContactGivenNameKey,
    CNContactFamilyNameKey,
    CNContactNicknameKey,
    CNContactJobTitleKey,
    CNContactOrganizationNameKey,
    CNContactPhoneNumbersKey,
    CNContactEmailAddressesKey,
    CNContactPostalAddressesKey,
    CNContactImageDataAvailableKey,
    CNContactThumbnailImageDataKey
  ];

  return keys;
}

/***** EXPORTED FUNCTIONS *****/

Napi::Value RequestAuthStatus(const Napi::CallbackInfo &info) {
  Napi::Env env = info.Env();
  Napi::Promise::Deferred deferred = Napi::Promise::Deferred::New(env);
  CNContactStore *addressBook = [[CNContactStore alloc] init];
  [addressBook requestAccessForEntityType:CNEntityTypeContacts completionHandler:^(BOOL granted, NSError *error){
    if (!error) {
      deferred.Resolve(Napi::Boolean::New(env, granted));
    } else {
      deferred.Reject(DecodeError(env, error));
    }
  }];
  return deferred.Promise();
}


Napi::Value GetAuthStatus(const Napi::CallbackInfo &info) {
  Napi::Env env = info.Env();
  std::string auth_status = "Not Determined";

  CNAuthorizationStatus status_for_entity = AuthStatus();

  if (status_for_entity == CNAuthorizationStatusAuthorized)
    auth_status = "Authorized";
  else if (status_for_entity == CNAuthorizationStatusDenied)
    auth_status = "Denied";
  else if (status_for_entity == CNAuthorizationStatusRestricted)
    auth_status = "Restricted";

  return Napi::Value::From(env, auth_status);
}

Napi::Promise GetAllContactIds(const Napi::CallbackInfo &info) {
  Napi::Env env = info.Env();
  Napi::Promise::Deferred deferred = Napi::Promise::Deferred::New(env);
  NSError *error = nil;
  CNContactStore *addressBook = [[CNContactStore alloc] init];
  NSPredicate *predicate = [CNContact predicateForContactsInContainerWithIdentifier:addressBook.defaultContainerIdentifier];
  NSArray *list = [addressBook unifiedContactsMatchingPredicate:predicate
                                                    keysToFetch:@[]
                                                          error:&error];
  if (error) {
    deferred.Reject(DecodeError(env, error));
  } else {
    int count = 0;
    Napi::Array identifiers = Napi::Array::New(env);
    for (CNContact *cncontact in list) {
      identifiers[count++] = std::string([[cncontact identifier] UTF8String]);
    }
    deferred.Resolve(identifiers);
  }
  return deferred.Promise();
}

Napi::Promise GetContactById(const Napi::CallbackInfo &info) {
  Napi::Env env = info.Env();
  Napi::Promise::Deferred deferred = Napi::Promise::Deferred::New(env);
  if (info.Length() < 1) {
    Napi::Object eobj = Napi::Object::New(env);
    eobj.Set("message", Napi::Value::From(env,"Parameter <indentifier> missing"));
    deferred.Reject(eobj);
  } else {
    std::string parameter = info[0].As<Napi::String>().Utf8Value();
    NSString *identifier = [NSString stringWithUTF8String:parameter.c_str()];
    CNContactStore *addressBook = [[CNContactStore alloc] init];
    NSError *error = nil;
    CNContact *cncontact = [addressBook unifiedContactWithIdentifier:identifier keysToFetch:GetContactKeys() error:&error];
    if (error) {
      deferred.Reject(DecodeError(env, error));
    } else if (!cncontact) {
      deferred.Reject(DecodeError(env, (NSError *)@{@"code": @200, @"localizedDescription":@"No such contact"}));
    } else {
      deferred.Resolve(CreateContact(env, cncontact));
    }
  }
  return deferred.Promise();
}

Napi::Promise GetAllContacts(const Napi::CallbackInfo &info) {
  Napi::Env env = info.Env();
  Napi::Promise::Deferred deferred = Napi::Promise::Deferred::New(env);
  Napi::Array contacts = Napi::Array::New(env);
  CNContactStore *addressBook = [[CNContactStore alloc] init];
  NSError *error = nil;

  NSPredicate *predicate = [CNContact predicateForContactsInContainerWithIdentifier:addressBook.defaultContainerIdentifier];
	NSArray *cncontacts = [addressBook unifiedContactsMatchingPredicate:predicate 
                                                          keysToFetch:GetContactKeys() 
                                                                error:&error];
  if (error) {
    deferred.Reject(DecodeError(env, error));
  } else {
    int count = 0;
    for (CNContact *cncontact in cncontacts) {
      contacts[count++] = CreateContact(env, cncontact);
    }
    deferred.Resolve(contacts);
  }
  return deferred.Promise();
}

Napi::Promise GetMe(const Napi::CallbackInfo &info) {
  Napi::Env env = info.Env();
  Napi::Promise::Deferred deferred = Napi::Promise::Deferred::New(env);
  CNContactStore *addressBook = [[CNContactStore alloc] init];
  NSError *error = nil;

  CNContact *cncontact = [addressBook unifiedMeContactWithKeysToFetch:GetContactKeys() error:&error];
  if (error) {
    deferred.Reject(DecodeError(env, error));
  } else if (!cncontact) {
    deferred.Reject(DecodeError(env, (NSError *)@{@"code": @200, @"localizedDescription":@"No such contact"}));
  } else {
    deferred.Resolve(CreateContact(env, cncontact));
  }
  return deferred.Promise();
}

Napi::Object Init(Napi::Env env, Napi::Object exports) {
  exports.Set(
    Napi::String::New(env, "requestAuthStatus"), Napi::Function::New(env, RequestAuthStatus)
  );
  exports.Set(
    Napi::String::New(env, "getAuthStatus"), Napi::Function::New(env, GetAuthStatus)
  );
  exports.Set(
    Napi::String::New(env, "getAllContactIds"), Napi::Function::New(env, GetAllContactIds)
  );
  exports.Set(
    Napi::String::New(env, "getAllContacts"), Napi::Function::New(env, GetAllContacts)
  );
  exports.Set(
    Napi::String::New(env, "getContactById"), Napi::Function::New(env, GetContactById)
  );
  exports.Set(
    Napi::String::New(env, "getMe"), Napi::Function::New(env, GetMe)
  );
  return exports;
}

NODE_API_MODULE(contacts, Init)