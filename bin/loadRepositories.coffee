#!/usr/bin/env coffee

_ = require 'underscore'
path = require "path"
yargs = require "yargs"
Promise = require 'bluebird'
createDependencies = require '../helper/dependencies'
settingsLoader = require "../core/helper/settings"

Promise.longStackTraces() # slows down execution but simplifies debugging

argv = yargs
  .usage('Usage: $0 [options]')
  .options(
    "s":
      alias: "settings"
      type: "string"
      description: "Settings for dependencies (SWF binding, logger, etc)"
      demand: true
  )
  .strict()
  .argv

settings = settingsLoader path.resolve(process.cwd(), argv.settings)

RepositoriesLoader = require '../lib/RepositoriesLoader.coffee'
RepositoriesCollection = require '../lib/model/Repositories.coffee'
PackagesCollection = require '../lib/model/Packages.coffee'
FilesCollection = require '../lib/model/Files.coffee'
dependencies = createDependencies(settings, 'badge')

# ensureIndex
Repositories = new RepositoriesCollection dependencies.mongodb
Packages = new PackagesCollection dependencies.mongodb
Files = new FilesCollection dependencies.mongodb

loader = new RepositoriesLoader(settings, dependencies)

Promise.join Repositories.init(), Packages.init(), Files.init()
.then -> loader.run()