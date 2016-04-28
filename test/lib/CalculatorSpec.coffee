_ = require 'underscore'
Promise = require 'bluebird'
createDependencies = require '../../helper/dependencies'
settings = (require '../../core/helper/settings')("#{process.env.ROOT_DIR}/settings/test.json")
fs = require 'fs'
fixtures = JSON.parse fs.readFileSync "#{process.env.ROOT_DIR}/test/fixtures/Calculator.json", {encoding: 'UTF-8'}
Calculator = require '../../lib/Calculator.coffee'

describe 'Calculator', ->
	dependencies = createDependencies(settings, 'Calculator')

	mongodb = dependencies.mongodb
	RepositoriesCollection = mongodb.collection('Repositories')
	PackagesCollection = mongodb.collection('Packages')
	FilesCollection = mongodb.collection('Files')

	calculator = new Calculator(dependencies)

	beforeEach ->
		Promise.bind @
		.then -> Promise.all [
			RepositoriesCollection.remove()
			PackagesCollection.remove()
			FilesCollection.remove()
		]
		.then -> Promise.all(RepositoriesCollection.insert repository for repository in fixtures.Repositories)
		.then -> Promise.all(PackagesCollection.insert pack for pack in fixtures.Packages)
		.then -> Promise.all(FilesCollection.insert file for file in fixtures.Files)

	it "should insert one thousand of Repositories", ->
		@timeout 1000

		Promise.bind(@)
		.then -> calculator.run()
		.then -> RepositoriesCollection.findOne({url: 'http://test.com'})
		.then (repository) -> repository.users.should.be.equal 1
		.then -> RepositoriesCollection.findOne({url: 'http://test2.com'})
		.then (repository) -> repository.users.should.be.equal 2
