import {PACKAGE_NAME} from '../constants'

isTest = process.env.IOKA_IS_TEST or true

Meteor.settings.public[PACKAGE_NAME] = {
  isTest
}

Meteor.settings.private = {} unless Meteor.settings.private
Meteor.settings.private[PACKAGE_NAME] = {
  siteUrl: process.env.IOKA_SITE_URL or Meteor.absoluteUrl()
  secretKey: process.env.IOKA_SECRET_KEY
  callbackPathname: process.env.IOKA_CALLBACK_PATHNAME or 'ioka'
  currency: 'USD'
  language: 'EN'
  isTest
}

export getConfig = -> Meteor.settings.private[PACKAGE_NAME]