Promise = require 'bluebird'
Match = require 'mtr-match'
_ = require 'underscore'

module.exports = class
	constructor: (mongodb) ->
		@mongodb = mongodb
		@collection = mongodb.collection("Packages")

	init: ->
		@collection.ensureIndex {url: 1, manager: 1}

	upsert: (raw) ->
		object = @buildObject raw

		Promise.bind @
		.then -> @findByObject(object)
		.then (found) -> if found then @update(object) else @insert(object)

	insert: (object) ->
		@collection.insert object

	update: (object) ->
		@collection.update @_getSelector(object), {$set: {priority: object.priority, url: object.url, updatedAt: new Date()}}

	findByObject: (object) ->
		@collection.findOne @_getSelector object

	_getSelector: (object) ->
		_.pick object, 'name', 'manager'

	buildObject: (data) ->
		Match.check data, Match.ObjectIncluding
			name: String
			manager: String
			priority: Match.Optional Number
#			url: Match.Optional String

		now = new Date()

		object = _.defaults _.pick(data, 'name', 'manager', 'url', 'priority'),
			priority: 0

		_.extend object,
			createdAt: now
			updatedAt: now
