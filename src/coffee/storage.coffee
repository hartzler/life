# Defines the Storage, Local, Sync
# Note: try to be app agnostic (aka no tags/types)
#
# minimum obj:
# id, tag, ...

logger = new Util.Logger('Life::Storage','debug')
logger.debug("loading storage.js...")

class Storage
  constructor: (@local,@sync)->
    @logger = logger    # DI
    @sync.on_receive = (obj)=>
      @local.put(obj) # store local
      @on_obj(obj)    # raise event

  # delegate
  get: (id)->@local.get(id)
  list: (tag)->@local.list(tag)

  put: (obj,local_only)->
    existing = @local.get(obj.id)
    if existing isnt obj
      @logger.debug("storing obj: #{obj.toSource()}")
      # TODO: handle sync in an async way w/ retry!
      # first put local
      @local.put(obj)
      # then sync
      @sync.store(obj) unless local_only

  # events to override...
  on_obj: (obj)->


# interface
class Local
  get: (id)->
  put: (obj)->
  list: (tag)->

# non-persistent
class TestLocal
  constructor: (@logger)->
    @objects = {}
    @logger ||= new Util.Logger("Life::Storage::TestLocal","debug")

  # local
  get: (id)-> @objects[id]
  put: (obj)->
    @logger.debug("storing obj: #{obj.toSource()}")
    @objects[obj.id] = obj

  list: (tag)->
    (obj for id,obj of @objects when obj.tag is tag)

# interface
class Sync
  store: (obj)->
  on_receive: (obj)->

# dummy
class TestSync
  constructor: (@logger)->
    @logger ||= new Util.Logger("Life::Storage::TestSync","debug")
  store: (obj)->
    @logger.debug("sending obj: #{obj.toSource()}")
    @on_receive(obj) # simulate event...
  on_receive: (obj)->

# a sync over EmailBus...
class EmailSync
  constructor: (@bus,@encode,@decode)->
    @bus.on('receive', @receive)
    @logger = new Util.Logger("Life::Storage::EmailSync",'debug')

  store: (obj)->
    @logger.debug("storing: obj=#{obj.toSource()}")
    @encode obj, (base64)=>
      try
        @bus.send(tag:obj.tag,crypted:true,base64:base64,subject:"Sync Data")
      catch e
        @logger.error("error sending message via bus!  #{obj.toSource()}",e)
    
  receive: (base64,subject)=>
    if subject is "Sync Data"
      @decode base64, (obj)=>@on_receive(obj)

  # events to override...
  on_receive: (obj)->

# exports
window.Storage = Storage
window.TestLocal = TestLocal
window.TestSync = TestSync
window.EmailSync = EmailSync
