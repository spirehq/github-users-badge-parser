Promise = require 'bluebird'
Match = require 'mtr-match'
_ = require 'underscore'

module.exports = class
	constructor: (mongodb) ->
		@mongodb = mongodb
		@collection = mongodb.collection("Repositories")

	init: ->
		@collection.ensureIndex {url: 1}
		
	upsert: (raw) ->
		object = @buildObject raw

		Promise.bind @
		.then -> @findByObject(object)
		.then (found) -> if found then @update(object) else @insert(object)

	insert: (object) ->
		@collection.insert object

	update: (object) ->
		modifier = {$set: {updatedAt: new Date()}}
		modifier.$set.users = object.users if object.users 
		@collection.update @_getSelector(object), modifier

	findByObject: (object) ->
		@collection.findOne @_getSelector object

	_getSelector: (object) ->
		_.pick object, 'url'

	buildObject: (data) ->
		Match.check data, Match.ObjectIncluding
			html_url: String

		now = new Date()

		url: data.html_url
		users: 0
		createdAt: now
		updatedAt: now
