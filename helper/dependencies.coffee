_ = require "underscore"
Match = require "mtr-match"
createMongoDB = require "../core/helper/mongodb"
createLogger = require "../core/helper/logger"

module.exports = (settings, handle) ->
  Match.check settings, Object
  Match.check handle, String
  settings.mongodb.url = settings.mongodb.url.replace("%database%", handle)
  dependencies = {settings: settings}
  Object.defineProperties dependencies,
    mongodb: get: _.memoize -> createMongoDB dependencies.settings.mongodb
    logger: get: _.memoize -> createLogger dependencies.settings.logger
  dependencies
