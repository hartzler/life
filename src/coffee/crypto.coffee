logger = new Util.Logger('Life::Crypto','debug')
logger.debug("loading crypto.js...")

worker = new Worker("chrome://life/content/javascript/background.js")
worker.onmessage = (event)->
  logger.debug("async callback: #{event.data.toSource()}")
  callbacks[event.data.function].apply(null,event.data.params)
  delete callbacks[event.data.function]

callbacks={}
background= (f,params,callback)->
  callback_name=Util.uuid()
  callbacks[callback_name]=callback
  logger.debug("async call: #{f} w/ params: #{params.toSource()} callback: #{callback_name}")
  worker.postMessage(function:f,callback:callback_name,params:params)


class Crypto
  setkey: (prikeystr)->
    @key=cryptico.privateKeyFromString(prikeystr)

  private_key: ()->
    cryptico.privateKeyString(@key)

  public_key: ()->
    cryptico.publicKeyString(@key)
 
  public_key_id: ->
    cryptico.publicKeyID(@public_key())

  # have to do in a worker for now...
  generate: (passphrase, continuation)->
    logger.debug("generating private key...")
    background 'generate', [passphrase, 1024], (keystr)=>
      logger.debug("generated: #{keystr}")
      @setkey(keystr)
      continuation(keystr)

  # returns binary packet string
  encrypt: (plaintext, pubkeys, continuation)->
    background 'encrypt', [@private_key(), plaintext, pubkeys], continuation

  # takes an object from the result of @encrypt()
  decrypt: (packet, continuation)->
    background 'decrypt', [@private_key(), packet], continuation

# exports
window.Crypto = Crypto
