logger = new Util.Logger('Life::Crypto','debug')
logger.debug("loading crypto.js...")

# alter the cryptico a bit...


class Crypto
  constructor: (@key)->
 
  # have to do in a worker for now...
  #generate: ()->
  #  cryptico.generateRSAKey(Util.uuid()+Util.uuid()+new Date().getTime() , 2048)

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
        pk = cryptico.publicKeyFromString(publickey)
        keys.push [cryptico.publicKeyID(publickey), cryptico.b16to64(pk.encrypt(cryptico.bytes2string(aeskey)))]
      catch err
        return {status: "Invalid public key"}
    cipher = cryptico.encryptAESCBC(text, aeskey)
    signature = cryptico.b16to64(@key.signString(JSON.stringify(keys) + cipher, "sha256"))
    return {pubkey: @public_key(), cipher: cipher, keys: keys, signature: signature}

  # takes an object from the result of @encrypt()
  decrypt: (encrypted)->
    result = cryptico.encrypt(text,key)
    if result.signature is "verified"
      result.plaintext
    else
      "invalid signature."

# exports
window.Crypto = Crypto
