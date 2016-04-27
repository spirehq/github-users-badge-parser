_ = require 'underscore'
Promise = require 'bluebird'
createDependencies = require '../../helper/dependencies'
settings = (require '../../core/helper/settings')("#{process.env.ROOT_DIR}/settings/test.json")

RepoLoader = require '../stub/RepoLoaderStub.coffee'

describe 'RepoLoader', ->
	dependencies = createDependencies(settings, 'RepoLoader')

	mongodb = dependencies.mongodb
	RepositoriesCollection = mongodb.collection('Repositories')
	PackagesCollection = mongodb.collection('Packages')
	FilesCollection = mongodb.collection('Files')

	repoLoader = undefined

	beforeEach ->
		repoLoader = new RepoLoader settings.github, dependencies

		Promise.bind @
		.then -> Promise.all [
			RepositoriesCollection.remove()
			PackagesCollection.remove()
			FilesCollection.remove()
		]

	it "should insert one thousand of Repositories", ->
		@timeout 100000

		new Promise (resolve, reject) ->
			nock.back 'test/fixtures/RepoLoader.json', (recordingDone) ->
				Promise.bind(@)
				.then -> repoLoader.syncRepositories()
				.then -> RepositoriesCollection.find().count()
				.then (count) -> count.should.be.equal 1000
				.then @assertScopesFinished
				.then resolve
				.catch reject
				.finally recordingDone

	it "should insert only one NPM Package", ->
		@timeout 100000

		new Promise (resolve, reject) ->
			nock.back 'test/fixtures/RepoLoader.json', (recordingDone) ->
				Promise.bind(@)
				.then -> repoLoader.syncRepositories()
				.then -> PackagesCollection.find().count()
				.then (count) -> count.should.be.equal 1
				.then @assertScopesFinished
				.then resolve
				.catch reject
				.finally recordingDone

	it "should insert only one File", ->
		@timeout 100000

		new Promise (resolve, reject) ->
			nock.back 'test/fixtures/RepoLoader.json', (recordingDone) ->
				Promise.bind(@)
				.then -> repoLoader.syncRepositories()
				.then -> FilesCollection.find().count()
				.then (count) -> count.should.be.equal 1
				.then -> FilesCollection.findOne()
				.then (file) ->
					file.name.should.be.equal 'package.json'
					file.packages.length.should.be.equal 5
				.then @assertScopesFinished
				.then resolve
				.catch reject
				.finally recordingDone
