_ = require 'underscore'
Promise = require 'bluebird'
createDependencies = require '../../helper/dependencies'
settings = (require '../../core/helper/settings')("#{process.env.ROOT_DIR}/settings/test.json")

RepoLoader = require '../stub/RepoLoaderStub.coffee'

describe 'RepoLoader', ->
	dependencies = createDependencies(settings, 'RepoLoader')

	mongodb = dependencies.mongodb;

	RepositoriesCollection = mongodb.collection("Repositories")

	repoLoader = new RepoLoader settings.github, dependencies

	beforeEach ->
		Promise.bind @
		.then -> Promise.all [
			RepositoriesCollection.remove()
		]

	it "should insert 300 hundred of Repositories", ->
		@timeout 10000

		new Promise (resolve, reject) ->
			nock.back 'test/fixtures/RepoLoader.json', (recordingDone) ->
				Promise.bind(@)
				.then -> repoLoader.syncRepositories()
				.then -> RepositoriesCollection.find().count()
				.then (count) -> count.should.be.equal 300
				.then @assertScopesFinished
				.then resolve
				.catch reject
				.finally recordingDone
