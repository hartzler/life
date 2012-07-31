logger = new Util.Logger('Life::Crypto','debug')
logger.debug("loading crypto.js...")

# alter the cryptico a bit...


class Crypto
  setkey: (keystring)->
    @key = cryptico.privateKeyFromString(keystring)

  private_key: ->
    cryptico.privateKeyString(@key)
 
  # have to do in a worker for now...
  generate: (on_success)->
    logger.debug("generating private key...")
    worker = new Worker('chrome://life/content/javascript/generate.js')
    worker.onmessage= (event)=>
      logger.debug("generated: #{event.data}")
      @setkey(event.data)
      on_success(event.data)
    worker.postMessage(passphrase:Util.uuid()+new Date().getTime() , bits:512)

  public_key: ->
    cryptico.publicKeyString(@key)

  public_key_id: ->
    cryptico.publicKeyID(@public_key())

  # returns {cipher: "...", keys: [], signature: "..."}
  encrypt: (plaintext, pubkeys)->
    aeskey = cryptico.generateAESKey()
    keys = []
    for publickey in pubkeys
      try
        logger.debug("encrypting aes key #{cryptico.b64to16(cryptico.b256to64(cryptico.bytes2string(aeskey)))} with publickey #{publickey}")
        pk = cryptico.publicKeyFromString(publickey)
        keys.push [cryptico.publicKeyID(publickey), cryptico.b16to64(pk.encrypt(cryptico.bytes2string(aeskey)))]
      catch err
        return {status: "Invalid public key"}
    cipher = cryptico.encryptAESCBC(plaintext, aeskey)
    signature = cryptico.b16to64(@key.signString(JSON.stringify(keys) + cipher, "sha256"))
    return btoa(JSON.stringify({cipher: cipher, keys: keys, signature: signature}))

  # takes an object from the result of @encrypt()
  decrypt: (encrypted)->
    o=JSON.parse(atob(encrypted))
    id = @public_key_id()
    logger.debug("decrypting: #{o.toSource()} with pubkey_id: #{id}")
    # todo verify signature
    keyblock = (key[1] for key in o.keys when key[0] is id)[0]
    logger.debug("decrypting keyblock: #{keyblock}")
    aeskeytext = @key.decrypt(cryptico.b64to16(keyblock))
    if aeskeytext
      logger.debug("decrypting using aes key: #{cryptico.b64to16(cryptico.b256to64(aeskeytext))}")
      cryptico.decryptAESCBC(o.cipher, cryptico.string2bytes(aeskeytext))
    else
      logger.error("unable to decrypt aes key!")
      throw "Unable to decrypt aes key"

# exports
window.Crypto = Crypto
