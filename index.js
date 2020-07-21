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
	return arr ? arr.map(i => {
		return {
			type: decodeLabel(i.type),
			value: i.value || null
		}
	}) : [];
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
	return contacts.getAllContacts().map(c => contactObject(c));
}

module.exports = {
  requestAuthStatus: contacts.requestAuthStatus,
  getAuthStatus: contacts.getAuthStatus,
  getAllContacts: getAllContacts,
  getMe: getMe
}