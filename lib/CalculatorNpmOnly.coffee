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
		@previousRss = process.memoryUsage().rss
		@maxRss = process.memoryUsage().rss
		@countUnused = 0
		@countUsed = 0
		@countInserted = 0

	run: ->
		currentRss = process.memoryUsage().rss
		@maxRss = Math.max(@maxRss, currentRss)
		@logger.info "Calculator:run", @skip, "Used", @countUsed, "Unused", @countUnused, "Updated", @countInserted, "(memory @ max: #{parseInt(@maxRss / 1024, 10)} KB, current: #{parseInt(currentRss / 1024, 10)} KB; change: #{if currentRss > @previousRss then "+" else ""}#{parseInt((currentRss - @previousRss) / 1024, 10)} KB)"
		@previousRss = currentRss
		Promise.bind @
		.then -> @PackagesCollection.find().limit(@limit).skip(@skip)
		.map (pack) -> Promise.join(pack, @calculateForPackage(pack), @updateRepository.bind(@))
		.then (results) ->
			@skip += @limit
			if results.length
				process.nextTick => @run()
			else
				@logger.info "Calculator:finished"
				process.exit(0)

	calculateForRepository: (repository) ->
		Promise.bind @
		.then -> @PackagesCollection.find {url: repository.url}
		.map @calculateForPackage, {concurrency: 1}
		.then (counts) -> counts.reduce(((acc, current) -> acc + current), 0)
		.then (users) -> repository.users = users
		.then -> @Repositories.update repository
		.thenReturn(true)

	calculateForPackage: (pack) ->
		@FilesCollection.count {manager: pack.manager, packages: pack.name}

	updateRepository: (pack, users) ->
		if users > 0
#			console.log "updateRepository", pack.url, users
			@countUsed++
		else
			@countUnused++
#		console.log "updateRepository", pack.url, users, @count++
		if pack.url
			url = pack.url.toLowerCase()
			url = url.replace(/\/$/, "")
			url = url.replace(/https:\/\/www.github.com/, "https://github.com")

			Promise.bind @
			.then -> @RepositoriesCollection.findOne({url})
			.then (repository) ->
				if repository
					@countInserted++
					repository.users = users
					@Repositories.update repository
				else
#					console.log "#{url}"
