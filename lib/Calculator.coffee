https = require 'https'
Promise = require 'bluebird'
_ = require 'underscore'
RepositoriesClass = require './model/Repositories.coffee'

module.exports = class
	constructor: (dependencies) ->
		@logger = dependencies.logger
		@Repositories = new RepositoriesClass(dependencies.mongodb)
		@RepositoriesCollection = dependencies.mongodb.collection('Repositories')
		@PackagesCollection = dependencies.mongodb.collection('Packages')
		@FilesCollection = dependencies.mongodb.collection('Files')
		@limit = 1000 # otherwise we're hogging memory like crazy
		@skip = 0
		@skipMax = 0
		@previousRss = process.memoryUsage().rss
		@maxRss = process.memoryUsage().rss

	run: ->
		currentRss = process.memoryUsage().rss
		@maxRss = Math.max(@maxRss, currentRss)
		@logger.info "Calculator:run", @skip, "(memory @ max: #{parseInt(@maxRss / 1024, 10)} KB, current: #{parseInt(currentRss / 1024, 10)} KB; change: #{if currentRss > @previousRss then "+" else ""}#{parseInt((currentRss - @previousRss) / 1024, 10)} KB)"
		@previousRss = currentRss
		Promise.bind @
		.then -> @Repositories.find().limit(@limit).skip(@skip)
		.map @calculateForRepository
		.then (results) ->
			@skip += @limit
			if results.length and (not @skipMax or @skipMax >= @skip)
				process.nextTick => @run()
			else
				process.exit(0)

	calculateForRepository: (repository) ->
		Promise.bind @
		.then -> @PackagesCollection.find {url: repository.url}
		.map @calculateForPackage
		.then (counts) -> counts.reduce(((acc, current) -> acc + current), 0)
		.then (users) -> repository.users = users
		.then -> @Repositories.update repository
		.thenReturn(true)

	calculateForPackage: (pack) ->
		@FilesCollection.count {manager: pack.manager, packages: pack.name}
