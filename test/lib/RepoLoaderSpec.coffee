_ = require "underscore"
Promise = require "bluebird"
createDependencies = require "../../helper/dependencies"
settings = (require "../../core/helper/settings")("#{process.env.ROOT_DIR}/settings/test.json")

RepoLoader = require "../../lib/RepoLoader.coffee"

describe "RepoLoader", ->
	dependencies = createDependencies(settings, "RepoLoader")

	mongodb = dependencies.mongodb;

	Repositories = mongodb.collection("Repositories")
	repoLoader = new RepoLoader settings.github

	it "should work", ->
		repoLoader.getRepositories (repos) ->
			console.log "Got #{repos.length}"
