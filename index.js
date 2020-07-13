const contacts = require('./build/Release/contacts.node')

function decodeLabel(label) {
	if (label.substring(0, 3) == "_$!") {
		let items = label.match(/<(.*)>/);
		if (items) {
			label = items[1];
		}
	}
	return label.toLowerCase();
}

function decodeLabeledArray(arr) {
	let newArr = [];
	if (arr && arr.length) {
		for (let n = 0; n < arr.length; n++) {
			newArr.push({
				type: decodeLabel(arr[n].type),
				value: arr[n].value || null
			});
		}
	}
	return newArr;
}

function contactObject(abObject) {
	return {
		...abObject,
		emails: decodeLabeledArray(abObject.emails),
		phoneNumbers: decodeLabeledArray(abObject.phoneNumbers),
		image: abObject.image || null
	};
}

function getMe() {
  let me = contacts.getMe();
  return Object.getOwnPropertyNames(me).length ? contactObject(me) : {};
}

function getAllContacts() {
	let contactList = [];
	contacts.getAllContacts().forEach(c => {
		contactList.push(contactObject(c))
	});
	return contactList;
}

module.exports = {
  requestAuthStatus: contacts.requestAuthStatus,
  getAuthStatus: contacts.getAuthStatus,
  getAllContacts: getAllContacts,
  getMe: getMe
}