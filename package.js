Package.describe({
  // Short two-sentence summary
  summary: 'Meteor ioka integration',
  version: '0.1.0',
  name: 'boomfly:meteor-ioka',
  git: 'https://github.com/boomfly/meteor-ioka'
});

Package.onUse((api) => {
  api.use('modules');
  api.use('webapp', 'server');
  api.use('underscore', 'server');
  api.use('ecmascript', 'server');
  api.use('coffeescript');

  api.mainModule('lib/server/ioka.coffee', 'server');
  api.mainModule('lib/client/index.coffee', 'client');
});
// This defines the tests for the package:
Package.onTest((api) => {
  // Sets up a dependency on this package.
  api.use('underscore', 'server');
  api.use('ecmascript', 'server');
  api.use('coffeescript');
  api.use('boomfly:meteor-cloudpayments');
  // Specify the source code for the package tests.
  api.addFiles('test/test.coffee', 'server');
});
