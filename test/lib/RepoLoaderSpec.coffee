_ = require "underscore"
Promise = require "bluebird"
createDependencies = require "../../helper/dependencies"
settings = (require "../../core/helper/settings")("#{process.env.ROOT_DIR}/settings/test.json")

RepoLoader = require "../stub/RepoLoaderStub.coffee"

describe "RepoLoader", ->
	dependencies = createDependencies(settings, "RepoLoader")

	mongodb = dependencies.mongodb;

	Repositories = mongodb.collection("Repositories")
	repoLoader = new RepoLoader settings.github

	it "should work", ->
		@timeout 10000

		new Promise (resolve, reject) ->
			nock.back "test/fixtures/RepoLoader.json", (recordingDone) ->
				Promise.bind(@)
				.then -> repoLoader.getRepositories (repos) -> console.log "Got #{repos.length}"
				.then @assertScopesFinished
				.then resolve
				.catch reject
				.finally recordingDone
