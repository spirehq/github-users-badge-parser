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
    "a":
      alias: "account"
      type: "string"
      description: "GitHub account (must be present in settings)"
      demand: true
    "f":
      alias: "from"
      type: "number"
      description: "From GitHub `since` parameter"
      demand: false
      default: 0
#    "t":
#      alias: "to"
#      type: "number"
#      description: "To GitHub `since` parameter"
#      demand: false
#      default: 0
  )
  .strict()
  .argv

settings = settingsLoader path.resolve(process.cwd(), argv.settings)
account = settings["accounts"][argv.account]
if not account then throw new Error("Can't find account '#{argv.account}' in settings")

RepositoriesLoader = require '../lib/RepositoriesLoader.coffee'
RepositoriesCollection = require '../lib/model/Repositories.coffee'
PackagesCollection = require '../lib/model/Packages.coffee'
FilesCollection = require '../lib/model/Files.coffee'
dependencies = createDependencies(settings, 'badge')

createSignalHandler("RepositoriesLoader", dependencies)

# ensureIndex
Repositories = new RepositoriesCollection dependencies.mongodb
Packages = new PackagesCollection dependencies.mongodb
Files = new FilesCollection dependencies.mongodb

loader = new RepositoriesLoader(settings, dependencies,
  account: account,
  from: argv.from
#  to: argv.to
)

Promise.join Repositories.init(), Packages.init()#, Files.init() DO NOT CREATE INDEX FOR Files Collection here!
.then -> loader.run()
