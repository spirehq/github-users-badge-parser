_ = require 'underscore'
__ = require 'lodash'
Promise = require 'bluebird'
requestAsync = Promise.promisify((require "request"), {multiArgs: true})
PackagesClass = require '../model/Packages.coffee'

MANAGER = 'npm'

module.exports = class
	constructor: (dependencies) ->
		@chunkSize = 1000
		@registry = dependencies.couchdb
		@logger = dependencies.logger
		@Packages = new PackagesClass(dependencies.mongodb)
		@counter = 0
		@overall = undefined
#		@retryOptions =
#			factor: 1
#			minTimeout: 30000

	run: ->
		Promise.bind @
		.then -> @registry.listAsync()
		.then (body) ->
			@overall = body.rows.length
			__.chunk body.rows, @chunkSize
		.map((chunk) ->
			Promise.resolve _.pluck chunk, 'key'
			.bind @
			.map (key) ->
				@registry.getAsync(key)
				.bind @
				.then (object) ->
					name = object.name
					return if not name # don't even try to handle entries with no names
					link = object.repository?.url
					url = @parse link if link
					if url
						requestAsync url
						.bind @
						.then -> @savePackage name, url
						.catch (e) -> console.log "Unreachable link #{url} (original: '#{link}')", e if e.code not in ['ENOTFOUND', 'ECONNRESET', 'ECONNREFUSED', 'EHOSTUNREACH', 'CERT_HAS_EXPIRED', 'ETIMEDOUT', 'UNABLE_TO_VERIFY_LEAF_SIGNATURE', 'EPROTO'] and not e.cert
					else
						@savePackage name, url
		
			.then -> @counter += @chunkSize; console.log "Chunk has been managed. #{@counter}/#{@overall}"
		, {concurrency: 1})

	parse: (link) ->
		# filter exceptional cases
		return if /^\s*$/.test link
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
	
		matches = link.match /^(ssh|git\+https|https|http|git)?(:\/*)?(.*@)?([^@]+?)(\.git)?$/
		if matches?[4]
			uri = matches[4]
			uri = uri.replace(/:/, '/')
			'https://' + uri
		else
			console.log 'Wrong link', link
			
	savePackage: (name, url) ->
		@Packages.upsert {manager: MANAGER, name, url}

