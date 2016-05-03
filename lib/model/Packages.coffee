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
		@collection.update @_getSelector(object), {$set: {url: object.url, updatedAt: new Date()}}

	findByObject: (object) ->
		@collection.findOne @_getSelector object

	_getSelector: (object) ->
		_.pick object, 'name', 'manager'

	buildObject: (data) ->
		Match.check data, Match.ObjectIncluding
			name: String
			manager: String
#			url: Match.Optional String

		now = new Date()

		_.extend _.pick(data, 'name', 'manager', 'url'),
			createdAt: now
			updatedAt: now
