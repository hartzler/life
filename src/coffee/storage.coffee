# Defines the storage local/remote for objs
# Note: try to be app agnostic (aka no tags)
#
# minimum obj:
# id, tag, ...

logger = new Util.Logger('Life::Storage','debug')
logger.debug("loading storage.js...")


class Storage
  constructor: (@local,@remote)->
    @logger = logger    # DI
    # delegate
    @get = (id)->@local.get(id)
    @list = (tag)->@local.list(tag)
    @remote.on_receive = (obj)=>@on_receive(obj)
    @remote.on_connect = ()=>@on_connect()

  put: (obj,local_only)->
    @logger.debug("storing obj: #{obj.toSource()}")
    # first put local
    @local.put(obj)
    # then remote
    @remote.send(obj) unless local_only

  # events
  on_receieve: (obj)->

  connect: (options)->
    @remote.connect(options)

# interface
class LocalStorage
  get: (id)->
  put: (obj)->
  list: (tag)->

# interface
class RemoteStorage
  connect: ()->
  disconnect: ()->
  put: (obj)->
  send: (obj)->
  on_receive: (obj)->
  on_connect: ()->
  on_disconnect: ()->

# implements LocalStorage && RemoteStorage
class TestStorage
  constructor: ()->
    @objects = {}
    @logger = new Util.Logger("Life::TestStorage","debug")

  # local
  get: (id)-> @objects[id]
  put: (obj)->
    @logger.debug("storing obj: #{obj.toSource()}")
    @objects[obj.id] = obj

  list: (tag)->
    (obj for id,obj of @objects when obj.tag is tag)

  # remote
  send: (obj)->@logger.debug("sending obj: #{obj.toSource()}")
  connect: (options)-> @on_connect()

  on_connect: ()->
  on_disconnect: ()->
  on_receive: (obj)->

# a remote storage using IMAP/SMTP
class EmailRemoteStorage
  constructor: (@stringify, @objify, @tos)->
    @logger = new Util.Logger("Life::EmailStorage",'debug')
    @client = new LifeClient()
    @client.logger = new Util.Logger("Life::EmailStorage::Client",'debug')
 
  connect: (options)->
    @client.notify = (obj)=>@on_receive(@objify(obj))
    @client.connect(options
      (()=>@on_connect()),
      ((msg)=>logger.error(msg)),
      (()=>if @client.isOnline() then @on_connect() else @on_disconnect()))

  # events
  on_receive: (obj)->
  on_connect: ()->
  on_disconnect: ()->
 
  send: (obj)->
    @client.send @tos(obj),
      "Private Message", # subject
      undefined, # related
      undefined, # html
      undefined, # txt
      @stringify(obj),
      obj.tag,
      ()=>@logger.debug("store success..."), # success
      (msg)=>@logger.debug(msg) # failure

# exports
window.Storage = Storage
window.TestStorage = TestStorage
window.EmailRemoteStorage = EmailRemoteStorage
