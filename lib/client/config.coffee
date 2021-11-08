import {PACKAGE_NAME} from '../constants'

export getConfig = -> Meteor.settings.public[PACKAGE_NAME]