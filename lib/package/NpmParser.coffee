_ = require 'underscore'
__ = require 'lodash'
Promise = require 'bluebird'
requestAsync = Promise.promisify((require "request"), {multiArgs: true})
PackagesClass = require '../model/Packages.coffee'
promiseRetry = require 'promise-retry'
sprintf = require("sprintf-js").sprintf
moment = require "moment"
require "moment-duration-format"

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
#		.then -> @registry.viewAsync("badge", "list", {limit: 10, start_key: '"003"'})
#		.then (result) -> console.log result.rows
		.tap -> @startedAt = new Date()
		.then -> @registry.listAsync()
		.then (body) -> body.rows
		.tap (rows) -> @overall = rows.length
		.then (rows) -> __.chunk rows, @chunkSize
		.map @handleChunk, {concurrency: 1}

	replicate: ->
		@db.replicateAsync @settings.source, @settings.target, {create_target: true}

	handleChunk: (chunk) ->
		Promise.bind @
		.return _.pluck chunk, 'key'
		.map @handlePackage, {concurrency: 5}
		.tap -> @counter += @chunkSize
		.tap @usage

	handlePackage: (key) ->
		promiseRetry (retry, number) =>
			Promise.bind @
			.then -> @registry.getAsync(key)
			.then (object) ->
				name = object.name
				return if not name # don't even try to handle entries with no names
				link = object.repository?.url
				url = @parse link if link
				@save name, url
			.tap -> @logger.log "Package #{key}"
			.catch (error) ->
				retry(error)

	usage: ->
		currentRss = process.memoryUsage().rss
		@maxRss = Math.max(@maxRss, currentRss)
		@previousRss = currentRss

		completed = @counter / @overall
		timeSpent = new Date().getTime() - @startedAt
		estimatedFinishedAt = timeSpent / completed - timeSpent

		@logger.info "FilesLoader:run", "#{@counter}/#{@overall}", "finishing in #{moment.duration(estimatedFinishedAt).format("h[h] mm[m] ss[s]")}", "completed: #{sprintf("%.2f", completed * 100)}%, timeSpent: #{moment.duration(timeSpent).format("h[h] mm[m] ss[s]")}, memory: #{parseInt(currentRss / 1024, 10)} / #{parseInt(@maxRss / 1024, 10)} KB)"

	parse: (link) ->
		# filter exceptional cases
		return false if link in [
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

		return false if /^\s*$/.test link

		matches = link.match /^(ssh|git\+https|https|http|git)?(:\/*)?(.*@)?([^@]+?)(\.git)?$/
		if matches?[4]
			uri = matches[4]
			uri = uri.replace(/:/, '/')
			url = 'https://' + uri

			return false if not @validateUrl url
			url
		else
			@logger.warn 'Wrong link', link

	validateUrl: (url) ->
		nonIP = /^https:\/\/[^\/]+\.[a-zA-Z]{2,}\/.*$/.test url
		generic = new RegExp("^(http|https|ftp)\://([a-zA-Z0-9\.\-]+(\:[a-zA-Z0-9\.&amp;%\$\-]+)*@)*((25[0-5]|2[0-4][0-9]|[0-1]{1}[0-9]{2}|[1-9]{1}[0-9]{1}|[1-9])\.(25[0-5]|2[0-4][0-9]|[0-1]{1}[0-9]{2}|[1-9]{1}[0-9]{1}|[1-9]|0)\.(25[0-5]|2[0-4][0-9]|[0-1]{1}[0-9]{2}|[1-9]{1}[0-9]{1}|[1-9]|0)\.(25[0-5]|2[0-4][0-9]|[0-1]{1}[0-9]{2}|[1-9]{1}[0-9]{1}|[0-9])|([a-zA-Z0-9\-]+\.)*[a-zA-Z0-9\-]+\.(com|edu|gov|int|mil|net|org|biz|arpa|info|name|pro|aero|coop|museum|[a-zA-Z]{2}))(\:[0-9]+)*(/($|[a-zA-Z0-9\.\,\?\'\\\+&amp;%\$#\=~_\-]+))*$").test url
		nonIP and generic

	save: (name, url) ->
		object = {name}
		object.url = url if url
		return @savePackage object

		# or

#		if object.url
#			requestAsync object.url
#			.bind @
#			.spread (response, body) ->
#				switch response.statusCode
#					when 200
#						@savePackage object
#						.return [response, body]
#					else
#						error = new Error("NpmParser:_requestAsync:invalidStatusCode")
#						error.details =
#							statusCode: response.statusCode
#							headers: response.headers
#							body: body
#						throw error
#			.catch (e) -> @logger.warn "Unreachable link '#{uri}'" if e.code not in ['ENOTFOUND', 'ECONNRESET', 'ECONNREFUSED', 'EHOSTUNREACH', 'CERT_HAS_EXPIRED', 'ETIMEDOUT', 'UNABLE_TO_VERIFY_LEAF_SIGNATURE', 'EPROTO'] and not e.cert
#		else
#			@savePackage object

	savePackage: (object) ->
		@Packages.upsert _.extend {manager: MANAGER}, object
