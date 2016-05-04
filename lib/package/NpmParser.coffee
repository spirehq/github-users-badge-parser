_ = require 'underscore'
__ = require 'lodash'
Promise = require 'bluebird'
requestAsync = Promise.promisify((require "request"), {multiArgs: true})
PackagesClass = require '../model/Packages.coffee'

MANAGER = 'npm'

module.exports = class
	constructor: (dependencies, settings) ->
		@settings = settings
		@chunkSize = 1000
		@db = dependencies.couchdb
		@registry = Promise.promisifyAll @db.use settings.database
		@logger = dependencies.logger
		@Packages = new PackagesClass(dependencies.mongodb)
		@counter = 0
		@overall = undefined
		@previousRss = process.memoryUsage().rss
		@maxRss = process.memoryUsage().rss

	run: ->
		Promise.bind @
		.then @replicate
		.tap -> @logger.verbose "CouchDB #{@settings.database} has been replicated"
		.then -> @registry.listAsync()
		.then (body) -> body.rows
		.tap (rows) -> @overall = rows.length
		.then (rows) -> __.chunk rows, @chunkSize
		.map @handleChunk, {concurrency: 1}

	replicate: ->
		@db.replicateAsync "https://skimdb.npmjs.com/registry", "http://admin:password@127.0.0.1:5984/registry", {create_target: true}

	handleChunk: (chunk) ->
		Promise.bind @
		.tap ->
			currentRss = process.memoryUsage().rss
			@maxRss = Math.max(@maxRss, currentRss)
			@logger.verbose "(memory @ max: #{parseInt(@maxRss / 1024, 10)} KB, current: #{parseInt(currentRss / 1024, 10)} KB; change: #{if currentRss > @previousRss then "+" else ""}#{parseInt((currentRss - @previousRss) / 1024, 10)} KB)"
			@previousRss = currentRss
		.return _.pluck chunk, 'key'
		.map @handlePackage, {concurrency: 5}
		.tap -> @counter += @chunkSize; @logger.verbose "Chunk has been managed #{@counter}/#{@overall}"

	handlePackage: (key) ->
		Promise.bind @
		.then -> @registry.getAsync(key)
		.then (object) ->
			name = object.name
			return if not name # don't even try to handle entries with no names
			link = object.repository?.url
			url = @parse link if link
			@save name, url
		.tap -> @logger.log "Package #{key}"

	parse: (link) ->
		# filter exceptional cases
		return if link in [
			'(none)'
			'https:///(none)'
			'https:///%20rep'
			'https:///%20repository'
			'/home/test/package.json'
			'git repository'
			'git rep'
		]
	
		# drop quotas
		link = link.replace /['"\(\)]+/, ''

		return if /^\s*$/.test link

		matches = link.match /^(ssh|git\+https|https|http|git)?(:\/*)?(.*@)?([^@]+?)(\.git)?$/
		if matches?[4]
			uri = matches[4]
			uri = uri.replace(/:/, '/')
		else
			@logger.warn 'Wrong link', link

	save: (name, uri) ->
		object = {name}
		object.url = 'https://' + uri if uri
		return @savePackage object

		# or

		if object.url
			requestAsync object.url
			.bind @
			.then -> @savePackage object
			.catch (e) -> @logger.warn "Unreachable link '#{uri}'", e if e.code not in ['ENOTFOUND', 'ECONNRESET', 'ECONNREFUSED', 'EHOSTUNREACH', 'CERT_HAS_EXPIRED', 'ETIMEDOUT', 'UNABLE_TO_VERIFY_LEAF_SIGNATURE', 'EPROTO'] and not e.cert
		else
			@savePackage object

	savePackage: (object) ->
		@Packages.upsert _.extend {manager: MANAGER}, object
