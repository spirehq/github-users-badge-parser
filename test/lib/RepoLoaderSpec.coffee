_ = require "underscore"
Promise = require "bluebird"
createDependencies = require "../../helper/dependencies"
settings = (require "../../core/helper/settings")("#{process.env.ROOT_DIR}/settings/test.json")

RepoLoader = require "../../lib/RepoLoader.coffee"

describe "RepoLoader", ->
	dependencies = createDependencies(settings, "RepoLoader")

	mongodb = dependencies.mongodb;

	Repositories = mongodb.collection("Repositories")

	it "should work", ->
		Promise.bind(@)
		.then -> Repositories.insert
			name: "Test"
		.then -> Repositories.find({}).count()
		.then -> console.log arguments
