#include <napi.h>
#import <Contacts/Contacts.h>

/***** HELPERS *****/

Napi::Array GetEmailAddresses(Napi::Env env, CNContact *cncontact) {
  int num_email_addresses = [[cncontact emailAddresses] count];

  Napi::Array email_addresses = Napi::Array::New(env, num_email_addresses);
  NSArray <CNLabeledValue<NSString*>*> *emailAddresses = [cncontact emailAddresses];
  for (int i = 0; i < num_email_addresses; i++) {
    CNLabeledValue<NSString*> *email_address = [emailAddresses objectAtIndex:i];
    Napi::Object email = Napi::Object::New(env);
    NSString *label = [email_address label];
    NSString *value = [email_address value];
    email.Set("type", std::string([label UTF8String]));
    email.Set("value", std::string([value UTF8String]));
    email_addresses[i] = email;
  }

  return email_addresses;
}

Napi::Array GetPhoneNumbers(Napi::Env env, CNContact *cncontact) {
  int num_phone_numbers = [[cncontact phoneNumbers] count];

  Napi::Array phone_numbers = Napi::Array::New(env, num_phone_numbers);
  NSArray <CNLabeledValue<CNPhoneNumber*>*> *phoneNumbers = [cncontact phoneNumbers];
  for (int i = 0; i < num_phone_numbers; i++) {
    CNLabeledValue<CNPhoneNumber*> *cnphone = [phoneNumbers objectAtIndex:i];
    Napi::Object phone = Napi::Object::New(env);
    NSString *label = [cnphone label];
    CNPhoneNumber *number = [cnphone value];
    phone.Set("type", std::string([label UTF8String]));
    phone.Set("value", std::string([[number stringValue] UTF8String]));
    phone_numbers[i] = phone;
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
  } else {
    contact.Set("image", "");
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

Napi::Array GetAllContacts(const Napi::CallbackInfo &info) {
  Napi::Env env = info.Env();
  Napi::Array contacts = Napi::Array::New(env);
  CNContactStore *addressBook = [[CNContactStore alloc] init];
  
  if (AuthStatus() != CNAuthorizationStatusAuthorized)
    return contacts;

  NSPredicate *predicate = [CNContact predicateForContactsInContainerWithIdentifier:addressBook.defaultContainerIdentifier];
	NSArray *cncontacts = [addressBook unifiedContactsMatchingPredicate:predicate 
                                                          keysToFetch:GetContactKeys() 
                                                                error:nil];
  
  int num_contacts = [cncontacts count];
  for (int i = 0; i < num_contacts; i++) {
    CNContact *cncontact = [cncontacts objectAtIndex:i];
    contacts[i] = CreateContact(env, cncontact);
  }

  return contacts;
}

Napi::Object GetMe(const Napi::CallbackInfo &info) {
  Napi::Env env = info.Env();
  Napi::Object noContact = Napi::Object::New(env);
  if (AuthStatus() != CNAuthorizationStatusAuthorized)
    return noContact;

  CNContactStore *addressBook = [[CNContactStore alloc] init];

  CNContact *cncontact = [addressBook unifiedMeContactWithKeysToFetch:GetContactKeys() error:nil];
  if (!cncontact) {
    return noContact;
  }
  return CreateContact(env, cncontact);
}

Napi::Object Init(Napi::Env env, Napi::Object exports) {
  exports.Set(
    Napi::String::New(env, "getAuthStatus"), Napi::Function::New(env, GetAuthStatus)
  );
  exports.Set(
    Napi::String::New(env, "getAllContacts"), Napi::Function::New(env, GetAllContacts)
  );
  exports.Set(
    Napi::String::New(env, "getMe"), Napi::Function::New(env, GetMe)
  );
  return exports;
}

NODE_API_MODULE(contacts, Init)