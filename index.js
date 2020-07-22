const contacts = require('./build/Release/contacts.node')

module.exports = {
  requestAuthStatus: contacts.requestAuthStatus,
  getAuthStatus: contacts.getAuthStatus,
  getAllContactIds: contacts.getAllContactIds,
  getAllContacts: contacts.getAllContacts,
  getContactById: contacts.getContactById,
  getMe: contacts.getMe
}