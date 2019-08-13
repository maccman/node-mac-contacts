#include <napi.h>
#import <Contacts/Contacts.h>

/***** HELPERS *****/

Napi::Array GetEmailAddresses(Napi::Env env, CNContact *cncontact) {
  int num_email_addresses = [[cncontact emailAddresses] count];

  Napi::Array email_addresses = Napi::Array::New(env, num_email_addresses);
  NSArray <CNLabeledValue<NSString*>*> *emailAddresses = [cncontact emailAddresses];
  for (int i = 0; i < num_email_addresses; i++) {
    CNLabeledValue<NSString*> *email_address = [emailAddresses objectAtIndex:i];
    email_addresses[i] = std::string([[email_address value] UTF8String]);
  }

  return email_addresses;
}

Napi::Array GetPhoneNumbers(Napi::Env env, CNContact *cncontact) {
  int num_phone_numbers = [[cncontact phoneNumbers] count];

  Napi::Array phone_numbers = Napi::Array::New(env, num_phone_numbers);
  NSArray <CNLabeledValue<CNPhoneNumber*>*> *phoneNumbers = [cncontact phoneNumbers];
  for (int i = 0; i < num_phone_numbers; i++) {
    CNLabeledValue<CNPhoneNumber*> *phone = [phoneNumbers objectAtIndex:i];
    CNPhoneNumber *number = [phone value];
    phone_numbers[i] = std::string([[number stringValue] UTF8String]);
  }

  return phone_numbers;
}

Napi::Array GetPostalAddresses(Napi::Env env, CNContact *cncontact) {
  int num_postal_addresses = [[cncontact postalAddresses] count];
  Napi::Array postal_addresses = Napi::Array::New(env, num_postal_addresses);

  CNPostalAddressFormatter *formatter = [[CNPostalAddressFormatter alloc] init];
  NSArray *postalAddresses = (NSArray*)[[cncontact postalAddresses] valueForKey:@"value"];
  for (int i = 0; i < num_postal_addresses; i++) {
    CNPostalAddress *address = [postalAddresses objectAtIndex:i];
    NSString *addr_string = [formatter stringFromPostalAddress:address];
    postal_addresses[i] = std::string([addr_string UTF8String]);
  }

  return postal_addresses;
}

std::string GetBirthday(CNContact *cncontact) {
  std::string result;

  NSDate *birth_date = [[cncontact birthday] date];
  NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
  [formatter setDateFormat:@"yyyy-MM-dd"];

  NSString *birthday = [formatter stringFromDate:birth_date];  
  if (birthday)
    result = std::string([birthday UTF8String]);
  
  return result;
}

Napi::Object CreateContact(Napi::Env env, CNContact *cncontact) {
  Napi::Object contact = Napi::Object::New(env);

  contact.Set("firstName", std::string([[cncontact givenName] UTF8String]));
  contact.Set("lastName", std::string([[cncontact familyName] UTF8String]));
  contact.Set("nickname", std::string([[cncontact nickname] UTF8String]));

  std::string birthday = GetBirthday(cncontact);
  contact.Set("birthday", birthday.empty() ? "" : birthday);

  // Populate phone number array
  Napi::Array phone_numbers = GetPhoneNumbers(env, cncontact);
  contact.Set("phoneNumbers", phone_numbers);

  // Populate email address array
  Napi::Array email_addresses = GetEmailAddresses(env, cncontact);
  contact.Set("emailAddresses", email_addresses);

  // Populate postal address array
  Napi::Array postal_addresses = GetPostalAddresses(env, cncontact);
  contact.Set("postalAddresses", postal_addresses);

  return contact;
}

NSArray* ParsePhoneNumbers(Napi::Array phone_number_data) {
  NSMutableArray *phone_numbers = [[NSMutableArray alloc] init];

  int data_length = static_cast<int>(phone_number_data.Length());
  for (int i = 0; i < data_length; i++) {
    std::string number_str = phone_number_data.Get(i).As<Napi::String>().Utf8Value();
    NSString *number = [NSString stringWithUTF8String:number_str.c_str()];
    CNPhoneNumber *phone_number = [CNPhoneNumber phoneNumberWithStringValue:number];
    CNLabeledValue *labeled_value = [CNLabeledValue labeledValueWithLabel:@"Home" value:phone_number];
    [phone_numbers addObject:labeled_value];
  }

  return phone_numbers;
}

NSArray* ParseEmailAddresses(Napi::Array email_address_data) {
  NSMutableArray *email_addresses = [[NSMutableArray alloc] init];

  int data_length = static_cast<int>(email_address_data.Length());
  for (int i = 0; i < data_length; i++) {
    std::string email_str = email_address_data.Get(i).As<Napi::String>().Utf8Value();
    NSString *email = [NSString stringWithUTF8String:email_str.c_str()];
    CNLabeledValue *labeled_value = [CNLabeledValue labeledValueWithLabel:@"Home" value:email];
    [email_addresses addObject:labeled_value];
  }

  return email_addresses;
}

NSDateComponents* ParseBirthday(std::string birth_day) {
  NSString *bday = [NSString stringWithUTF8String:birth_day.c_str()];
  NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
  [formatter setDateFormat:@"yyyy-MM-dd"];

  NSDate *bday_date = [formatter dateFromString:bday];

  NSCalendar *cal = [NSCalendar currentCalendar];
  unsigned unitFlags = NSYearCalendarUnit | NSMonthCalendarUnit |  NSDayCalendarUnit;
  NSDateComponents *birthday_components = [cal components:unitFlags fromDate:bday_date];

  return birthday_components;
}

CNAuthorizationStatus AuthStatus() {
  CNEntityType entityType = CNEntityTypeContacts;
  return [CNContactStore authorizationStatusForEntityType:entityType];
}

NSArray* GetContactKeys() {
  NSArray *keys = @[
    CNContactGivenNameKey,
    CNContactFamilyNameKey,
    CNContactPhoneNumbersKey,
    CNContactEmailAddressesKey,
    CNContactNicknameKey,
    CNContactPostalAddressesKey,
    CNContactBirthdayKey
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

Napi::Array GetContactsByName(const Napi::CallbackInfo &info) {
  Napi::Env env = info.Env();
  Napi::Array contacts = Napi::Array::New(env);
  CNContactStore *addressBook = [[CNContactStore alloc] init];

  if (AuthStatus() != CNAuthorizationStatusAuthorized)
    return contacts;

  std::string name_string = info[0].As<Napi::String>().Utf8Value();
  NSString *name = [NSString stringWithUTF8String:name_string.c_str()];
  NSPredicate *predicate = [CNContact predicateForContactsMatchingName:name];

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

Napi::Boolean AddNewContact(const Napi::CallbackInfo &info) {
  Napi::Env env = info.Env();
  CNContactStore *addressBook = [[CNContactStore alloc] init];

  if (AuthStatus() != CNAuthorizationStatusAuthorized)
    return Napi::Boolean::New(env, false);

  CNMutableContact *contact = [[CNMutableContact alloc] init];
  Napi::Object contact_data = info[0].As<Napi::Object>();

  if (contact_data.Has("firstName")) {
    std::string first_name = contact_data.Get("firstName").As<Napi::String>().Utf8Value();
    [contact setGivenName:[NSString stringWithUTF8String:first_name.c_str()]];
  }

  if (contact_data.Has("lastName")) {
    std::string last_name = contact_data.Get("lastName").As<Napi::String>().Utf8Value();
    [contact setFamilyName:[NSString stringWithUTF8String:last_name.c_str()]];
  }

  if (contact_data.Has("nickname")) {
    std::string nick_name = contact_data.Get("nickname").As<Napi::String>().Utf8Value();
    [contact setNickname:[NSString stringWithUTF8String:nick_name.c_str()]];
  }

  if (contact_data.Has("birthday")) {
    std::string birth_day = contact_data.Get("birthday").As<Napi::String>().Utf8Value();
    NSDateComponents *birthday_components = ParseBirthday(birth_day);
    [contact setBirthday:birthday_components];
  }

  if (contact_data.Has("phoneNumbers")) {
    Napi::Array phone_number_data = contact_data.Get("phoneNumbers").As<Napi::Array>();
    NSArray *phone_numbers = ParsePhoneNumbers(phone_number_data);
    [contact setPhoneNumbers:[NSArray arrayWithArray:phone_numbers]];
  }

  if (contact_data.Has("emailAddresses")) {
    Napi::Array email_address_data = contact_data.Get("emailAddresses").As<Napi::Array>();
    NSArray *email_addresses = ParseEmailAddresses(email_address_data);
    [contact setEmailAddresses:[NSArray arrayWithArray:email_addresses]];
  }

  CNSaveRequest *request = [[CNSaveRequest alloc] init];
  [request addContact:contact toContainerWithIdentifier:nil];
  bool success = [addressBook executeSaveRequest:request error:nil];

  return Napi::Boolean::New(env, success);
}

Napi::Value DeleteContactByName(const Napi::CallbackInfo &info) {
  Napi::Env env = info.Env();
  CNContactStore *addressBook = [[CNContactStore alloc] init];

  if (AuthStatus() != CNAuthorizationStatusAuthorized)
    return Napi::Boolean::New(env, false);

  std::string name_string = info[0].As<Napi::String>().Utf8Value();
  NSString *name = [NSString stringWithUTF8String:name_string.c_str()];
  NSPredicate *predicate = [CNContact predicateForContactsMatchingName:name];

  NSArray *cncontacts = [addressBook unifiedContactsMatchingPredicate:predicate
                                                                keysToFetch:GetContactKeys()
                                                                      error:nil];
  
  // Place the burden on end-users to specify name enough that
  // the first contact to be returned from a predicate search would
  // be the person they want to delete
  CNContact *contact = (CNContact*)[cncontacts objectAtIndex:0];
  CNSaveRequest *request = [[CNSaveRequest alloc] init];
  [request deleteContact:[contact mutableCopy]];
  
  bool success = [addressBook executeSaveRequest:request error:nil];

  return Napi::Boolean::New(env, success);
}

Napi::Object Init(Napi::Env env, Napi::Object exports) {
  exports.Set(
    Napi::String::New(env, "getAuthStatus"), Napi::Function::New(env, GetAuthStatus)
  );
  exports.Set(
    Napi::String::New(env, "getAllContacts"), Napi::Function::New(env, GetAllContacts)
  );
  exports.Set(
    Napi::String::New(env, "getContactsByName"), Napi::Function::New(env, GetContactsByName)
  );
  exports.Set(
    Napi::String::New(env, "addNewContact"), Napi::Function::New(env, AddNewContact)
  );
  exports.Set(
    Napi::String::New(env, "deleteContactByName"), Napi::Function::New(env, DeleteContactByName)
  );

  return exports;
}

NODE_API_MODULE(contacts, Init)