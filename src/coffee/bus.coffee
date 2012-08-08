# Defines the Bus interface
# Note: try to be app agnostic (aka no tags/types)
#
# minimum obj:
# id, tag, ...

logger = new Util.Logger('Life::Bus','debug')
logger.debug("loading bus.js...")

obj2encoded= (obj)->atob(JSON.stringify(obj))
encoded2obj= (encoded)->JSON.parse(btoa(encoded))

# interface
class Bus
  send: (msg,on_error)-> # this is kinda bogus.  each bus type will have its own msg format...
  on: (e,f)->

# dummy
class TestEmailBus extends Util.PubSub
  constructor: (@logger)->
    @logger ||= new Util.Logger("Life::Storage::TestBus",'debug')
  send: (msg)->@logger.debug("send: #{msg.toSource()}")
  on_receive: (msg)->@logger.debug("on_receive: #{msg.toSource()}")

# send/receive via SMTP/IMAP
class EmailBus extends Util.PubSub
  constructor: (@client,@crypto,@logger)->
    @client.notify = @receive
    @logger ||= new Util.Logger("Life::Storage::Bus",'debug')

  send: (msg,on_error)->
    @client.send(
      to:msg.to||[@client.options['email']], # default to self
      tag:msg.tag,
      txt:msg.txt,
      subject:msg.subject,
      crypted:msg.crypted,
      base64:msg.base64,
      (()->),
      on_error||((msg)->)
    )

  # event handler
  receive: (msg)=>
    try
      @pub('receive',msg.base64,msg.subject)
    catch e
      @logger.error("error parsing object from message #{msg.id}",e)
    

# exports
window.EmailBus= EmailBus
window.TestEmailBus= TestEmailBus
