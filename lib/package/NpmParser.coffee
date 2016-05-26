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
		@chunkSize = 1001 # the last one is an anchor for the next request
		@db = dependencies.couchdb
		@registry = Promise.promisifyAll @db.use settings.database
		@logger = dependencies.logger
		@Packages = new PackagesClass(dependencies.mongodb)
		@counter = 0
		@overall = undefined
		@mongoTime = 0
		@maxMongoTime = 0
		@mongoCounter = 0
		@couchTime = 0
		@maxCouchTime = 0
		@couchCounter = 0
		@previousRss = process.memoryUsage().rss
		@maxRss = process.memoryUsage().rss
		@count = 0

	run: ->
		new Promise (resolve, reject) =>
			Promise.bind @
			.then @replicate  
			.tap -> @logger.verbose "CouchDB #{@settings.database} has been replicated"
			.tap -> @startedAt = new Date()
			.then -> @next(resolve, reject, {})

	next: (resolve, reject, options) ->
		request = _.defaults(options, {limit: @chunkSize})
		couchStartedAt = undefined

		Promise.bind @
		.tap -> couchStartedAt = new Date()
		.then -> @registry.viewAsync("badge", "list", request)
		.tap -> diff = new Date() - couchStartedAt; @couchTime += diff; @maxCouchTime = Math.max(@maxCouchTime, diff); @couchCounter++
		.tap (result) -> @overall = result.total_rows
		.then (result) -> result.rows
		.then (rows) -> Promise.join @getAnchor(rows), @handlePackages(rows), @getNextChunk.bind(@, resolve, reject)
		.tap @usage
		.catch reject

	replicate: ->
		@db.replicateAsync @settings.source, @settings.target, {create_target: true}

	# Warning! Implicit mutation of incoming argument.
	getAnchor: (rows) ->
		rows.pop() if rows.length is @chunkSize

	getNextChunk: (resolve, reject, anchor) ->
		if anchor
			key = anchor.key
			process.nextTick => @next resolve, reject, {start_key: "\"#{key}\""}
		else
			resolve()

	handlePackages: (rows) ->
		Promise.bind @
		.return rows
		.map @handlePackage
		.tap (results) -> @counter += results.length

	handlePackage: (object) ->
		promiseRetry (retry, number) =>
			Promise.bind @
			.then ->
				name = object.key
				return if not name # don't even try to handle entries with no names
				link = object.value.url
				url = @parse link if link
				priority = object.value.priority or 0
				@save name, url, priority
			.catch (error) ->
				@logger.error error.message, _.extend({stack: error.stack}, error.details)
				retry(error)

	usage: ->
		currentRss = process.memoryUsage().rss
		@maxRss = Math.max(@maxRss, currentRss)
		@previousRss = currentRss

		completed = @counter / @overall
		timeSpent = new Date().getTime() - @startedAt
		estimatedFinishedAt = timeSpent / completed - timeSpent

		@logger.info "NpmParser:next", "#{@counter}/#{@overall}", "finishing in #{moment.duration(estimatedFinishedAt).format("h[h] mm[m] ss[s]")}", "(couch time @ mean: #{parseInt(@couchTime / @couchCounter, 10)}ms, max: #{@maxCouchTime}ms; mongo time @ mean: #{parseInt(@mongoTime / @mongoCounter, 10)}ms, max: #{@maxMongoTime}ms;", "completed: #{sprintf("%.2f", completed * 100)}%, timeSpent: #{moment.duration(timeSpent).format("h[h] mm[m] ss[s]")}, memory: #{parseInt(currentRss / 1024, 10)} / #{parseInt(@maxRss / 1024, 10)} KB)"

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
			url = url.trim()

			return false if not @validateUrl url
			url
		else
			@logger.warn 'Wrong link', link

	validateUrl: (url) ->
		nonIP = /^https:\/\/[^\/]+\.[a-zA-Z]{2,}\/.*$/.test url
		# DANGER! Performance issue!
		#generic = new RegExp("^(http|https|ftp)\://([a-zA-Z0-9\.\-]+(\:[a-zA-Z0-9\.&amp;%\$\-]+)*@)*((25[0-5]|2[0-4][0-9]|[0-1]{1}[0-9]{2}|[1-9]{1}[0-9]{1}|[1-9])\.(25[0-5]|2[0-4][0-9]|[0-1]{1}[0-9]{2}|[1-9]{1}[0-9]{1}|[1-9]|0)\.(25[0-5]|2[0-4][0-9]|[0-1]{1}[0-9]{2}|[1-9]{1}[0-9]{1}|[1-9]|0)\.(25[0-5]|2[0-4][0-9]|[0-1]{1}[0-9]{2}|[1-9]{1}[0-9]{1}|[0-9])|([a-zA-Z0-9\-]+\.)*[a-zA-Z0-9\-]+\.(com|edu|gov|int|mil|net|org|biz|arpa|info|name|pro|aero|coop|museum|[a-zA-Z]{2}))(\:[0-9]+)*(/($|[a-zA-Z0-9\.\,\?\'\\\+&amp;%\$#\=~_\-]+))*$").test url
		nonIP # and generic

	save: (name, url, priority) ->
		object = {name}
		object.url = url if url
		object.priority = priority

		mongoStartedAt = undefined
		Promise.bind @
		.tap -> mongoStartedAt = new Date()
		.then -> @savePackage object
		.tap -> diff = new Date() - mongoStartedAt; @mongoTime += diff; @maxMongoTime = Math.max(@maxMongoTime, diff); @mongoCounter++

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
		@Packages.insert @Packages.buildObject _.extend {manager: MANAGER}, object
