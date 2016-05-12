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
      demand: false
      default: 0
    "t":
      alias: "to"
      type: "number"
      description: "To MongoDB `skip` parameter"
      demand: false
      default: 0
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
      default: 0
    "e":
      alias: "end"
      type: "number"
      description: "End of range (for statistics)"
      demand: false
      default: 1
  )
  .strict()
  .argv

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
loader.timestamp = new Date(argv.startedAt)
loader.begin = argv.begin
loader.end = argv.end

Promise.join Repositories.init(), Packages.init(), Files.init()
.then -> loader.init()
.then -> loader.run()
.then ->
  # see http://stackoverflow.com/questions/24045414/node-program-with-promises-doesnt-finish
   dependencies.mongodb.close()
