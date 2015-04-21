Driver = require './driver'

{ EventEmitter } = require 'events'
_ = require 'underscore'
loglet = require 'loglet'

class NoPool 
  constructor: (@key, @type, driver, @connOptions, @options) ->
    self = @
    #loglet.log 'Easydbi.NoPool.ctor', @key, @type, @connOptions, @options
    @driver = class noPoolDriver extends driver
      @id = 0
  connect: (cb) ->
    #loglet.log 'Easydbi.NoPool.connect', @key, @connOptions
    conn = new @driver @key, @connOptions
    conn.connect cb 
  prepare: (call, options) ->
    proc = 
      if options?.query 
        (args, cb) ->
          @query options.query, args, cb 
      else if options?.exec
        (args, cb) ->
          @exec options.exec, args, cb 
      else if options instanceof Function 
        options
      else
        throw {error: 'invalid_prepare_option', call: call, options: options}
    @driver.prototype[call] = proc

# we will have 
class Pool extends EventEmitter
  @NoPool = NoPool
  @defaultOptions: 
    min: 0 
    max: 20
  constructor: (@key, @type, driver, @connOptions, @options) ->
    @options = _.extend {}, @constructor.defaultOptions, @options or {}
    self = @
    #loglet.log 'Easydbi.Pool.ctor', @key, @type
    @driver = class poolDriver extends driver
      @id = 0
      disconnect: (cb) ->
        self.makeAvailable @
    @total = [] # everything is managed here...
    @avail = [] # we keep track of what's currently available.
  connect: (cb) ->
    #loglet.log 'Pool.connect', @options, @total.length, @avail.length
    connectMe = (db) ->
      if db.isConnected()
        cb null, db
      else
        db.connect cb 
    if @avail.length > 0 
      db = @avail.shift()
      connectMe db
    else 
      @once 'available', connectMe
      if @total.length < @options.max
        db = new @driver @key, @connOptions 
        @total.push db
        @makeAvailable db
  prepare: (call, options) ->
    proc = 
      if options?.query 
        (args, cb) ->
          @query options.query, args, cb 
      else if options?.exec
        (args, cb) ->
          @exec options.exec, args, cb 
      else if (options instanceof Function) or (typeof(options) == 'function')
        options
      else
        throw {error: 'invalid_prepare_option', call: call, options: options}
    @driver.prototype[call] = proc
  makeAvailable: (db) ->
    if not _.contains @avail, db
      @avail.push db 
    @emit 'available', db

module.exports = Pool