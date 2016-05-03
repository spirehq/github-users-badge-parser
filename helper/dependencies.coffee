_ = require "underscore"
Match = require "mtr-match"
createMongoDB = require "../core/helper/mongodb"
createLogger = require "../core/helper/logger"
Promise = require 'bluebird'
Agentkeepalive = require 'agentkeepalive'
nanoConstructor = require('nano')

createCouchDB = (settings) ->
  agent = new Agentkeepalive
    maxSockets: 50
    maxKeepAliveRequests: 0
    maxKeepAliveTime: 30000
  nano = nanoConstructor
    url: settings.url
    requestDefaults: {agent}
  db = Promise.promisifyAll nano.db
  Promise.promisifyAll db.use settings.database

module.exports = (settings, handle) ->
  Match.check settings, Object
  Match.check handle, String
  settings.mongodb.url = settings.mongodb.url.replace("%database%", handle)
  dependencies = {settings: settings}
  Object.defineProperties dependencies,
    mongodb: get: _.memoize -> createMongoDB dependencies.settings.mongodb
    couchdb: get: _.memoize -> createCouchDB dependencies.settings.couchdb
    logger: get: _.memoize -> createLogger dependencies.settings.logger
  dependencies
