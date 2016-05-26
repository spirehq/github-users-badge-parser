#!/usr/bin/env coffee

path = require "path"
yargs = require "yargs"
createDependencies = require "../helper/dependencies"
settingsLoader = require "../core/helper/settings"
createSignalHandler = require "../helper/signal"
NpmParser = require '../lib/package/NpmParser.coffee'
PackagesCollection = require '../lib/model/Packages.coffee'
Promise = require 'bluebird'

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
dependencies = createDependencies(settings, 'badge')

createSignalHandler("NpmParser", dependencies)

# ensureIndex
Packages = new PackagesCollection dependencies.mongodb

parser = new NpmParser(dependencies, settings.couchdb)
Promise.bind @
.then -> Packages.drop()
.tap -> dependencies.logger.verbose "Collection Packages has been dropped"
.then -> parser.run()
.tap -> dependencies.logger.verbose "Parsing has been finished"
.then -> Packages.buildIndex()
.tap -> dependencies.logger.verbose "Index for collection Packages has been built"
.then ->
	dependencies.logger.verbose "LoadNpm is finished"
	
	# see http://stackoverflow.com/questions/24045414/node-program-with-promises-doesnt-finish
	dependencies.mongodb.close()
