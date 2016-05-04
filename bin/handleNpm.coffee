#!/usr/bin/env coffee

path = require "path"
yargs = require "yargs"
createDependencies = require '../helper/dependencies'
settingsLoader = require "../core/helper/settings"
NpmParser = require '../lib/package/NpmParser.coffee'

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

parser = new NpmParser(dependencies, settings.couchdb)
parser.run()
.then -> console.log "Done"
.catch (e) -> console.error "ERROR", e
.then -> process.exit(0)
