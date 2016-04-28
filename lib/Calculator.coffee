https = require 'https'
Promise = require 'bluebird'
_ = require 'underscore'
RepositoriesClass = require './model/Repositories.coffee'

module.exports = class
	constructor: (dependencies) ->
		@Repositories = new RepositoriesClass(dependencies.mongodb)
		@RepositoriesCollection = dependencies.mongodb.collection('Repositories')
		@PackagesCollection = dependencies.mongodb.collection('Packages')
		@FilesCollection = dependencies.mongodb.collection('Files')

	run: ->
		Promise.bind @
		.then -> @RepositoriesCollection.find()
		.map @calculateForRepository

	calculateForRepository: (repository) ->
		Promise.bind @
		.then -> @PackagesCollection.find {url: repository.url}
		.map @calculateForPackage
		.then (counts) -> counts.reduce(((acc, current) -> acc + current), 0)
		.then (users) -> repository.users = users
		.then -> @Repositories.update repository

	calculateForPackage: (pack) ->
		@FilesCollection.count {manager: pack.manager, packages: pack.name}
