#!/usr/bin/env coffee

_ = require 'underscore'
path = require "path"
yargs = require "yargs"
Promise = require 'bluebird'
createDependencies = require "../helper/dependencies"
settingsLoader = require "../core/helper/settings"
createSignalHandler = require "../helper/signal"

Promise.longStackTraces() # slows down execution but simplifies debugging

argv = yargs
  .usage('Usage: $0 [options]')
  .options(
    "s":
      alias: "settings"
      type: "string"
      description: "Settings for dependencies (SWF binding, logger, etc)"
      demand: true
    "f":
      alias: "from"
      type: "number"
      description: "From MongoDB `skip` parameter"
      demand: true
    "t":
      alias: "to"
      type: "number"
      description: "To MongoDB `skip` parameter"
      demand: true
    "S":
      alias: "startedAt"
      type: "number"
      description: "UNIX timestamp (for statistics)"
      demand: false
      default: new Date().getTime()
    "b":
      alias: "begin"
      type: "number"
      description: "Start of range (for statistics)"
      demand: false
    "e":
      alias: "end"
      type: "number"
      description: "End of range (for statistics)"
      demand: false
  )
  .strict()
  .argv

argv.begin ?= argv.from
argv.end ?= argv.to

settings = settingsLoader path.resolve(process.cwd(), argv.settings)

FilesLoader = require '../lib/FilesLoader.coffee'
RepositoriesCollection = require '../lib/model/Repositories.coffee'
PackagesCollection = require '../lib/model/Packages.coffee'
FilesCollection = require '../lib/model/Files.coffee'
dependencies = createDependencies(settings, 'badge')

createSignalHandler("FilesLoader", dependencies)

# ensureIndex
Repositories = new RepositoriesCollection dependencies.mongodb
Packages = new PackagesCollection dependencies.mongodb
Files = new FilesCollection dependencies.mongodb

loader = new FilesLoader(settings, dependencies)
loader.from = argv.from
loader.to = argv.to
loader.startedAt = argv.startedAt
loader.begin = argv.begin
loader.end = argv.end

Promise.join Repositories.init(), Packages.init()#, Files.init() DO NOT CREATE INDEX FOR Files Collection here!
.then -> loader.init()
.then -> loader.run()
.finally -> console.log "close"; dependencies.mongodb.close() # see http://stackoverflow.com/questions/24045414/node-program-with-promises-doesnt-finish
.then ->
  process.exit(0) # necessary to kill
.catch (error) ->
  dependencies.logger.error error.message, _.extend({stack: error.stack}, error.details)
  process.exit(1)
