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
    keys = {}
    for publickey in pubkeys
      try
        logger.debug("encrypting aes key #{cryptico.b64to16(cryptico.b256to64(cryptico.bytes2string(aeskey)))} with publickey #{publickey}")
        pk = cryptico.publicKeyFromString(publickey)
        keys[cryptico.publicKeyID(publickey)]=cryptico.b16to64(pk.encrypt(cryptico.bytes2string(aeskey)))
      catch err
        return {status: "Invalid public key"}
    cipher = cryptico.encryptAESCBC(plaintext, aeskey)
    signature = cryptico.b16to64(@key.signString(JSON.stringify(keys) + cipher, "sha256"))
    JSON.stringify({keys: keys, signature: signature, length: cipher.length}) + "\n" + cipher

  # takes an object from the result of @encrypt()
  decrypt: (packet)->
    header_length = packet.indexOf("\n")
    header = JSON.parse(packet.slice(0,header_length))
    cipher = packet.slice(header_length+1)
    id = @public_key_id()
    logger.debug("decrypting: header=#{header.toSource()} with pubkey_id=#{id}")
    # todo verify signature
    keyblock = header.keys[id]
    if keyblock
      logger.debug("decrypting keyblock: #{keyblock}")
      aeskeytext = @key.decrypt(cryptico.b64to16(keyblock))
    else
      logger.error("unable to find session key for public key id: #{id}")
      throw "Unable to find keyblock!"
    if aeskeytext
      logger.debug("decrypting using aes key: #{cryptico.b64to16(cryptico.b256to64(aeskeytext))}")
      cryptico.decryptAESCBC(cipher, cryptico.string2bytes(aeskeytext))
    else
      logger.error("unable to decrypt aes key!")
      throw "Unable to decrypt aes key"

# exports
window.Crypto = Crypto
