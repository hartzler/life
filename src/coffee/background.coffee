importScripts('cryptico.js')

log=(s)->dump("BACKGROUND: "); dump(s); dump("\n")

# respond to calls of format worker.postMessage([function, callback, params...])
self.onmessage = (event)->
  log("async received: #{event.data.toSource()}")
  result=background[event.data.function].apply(background,event.data.params)
  response=function:event.data.callback, params:[result]
  log("async response: #{response.toSource()}")
  self.postMessage(response)

# long running computations...
background=
  generate: (passphrase,bits)->
    log("generate: passphrase=#{passphrase} bits=#{bits}")
    key = cryptico.generateRSAKey(passphrase, bits)
    cryptico.privateKeyString(key)

  encrypt: (keystr, plaintext, pubkeys)->
    log("encrypt: keystr=#{keystr} plaintext=#{plaintext} pubkeys=#{(pubkeys||[]).toSource()}")
    key = cryptico.privateKeyFromString(keystr)
    encrypt(key, plaintext, pubkeys)

  decrypt: (keystr,packet)->
    log("decrypt: keystr=#{keystr} packet=#{packet}")
    key = cryptico.privateKeyFromString(keystr)
    id = cryptico.publicKeyID(cryptico.publicKeyString(key))
    decrypt(key,id,packet)

encrypt= (key, plaintext, pubkeys)->
  aeskey = cryptico.generateAESKey()
  keys = {}
  for publickey in pubkeys
    try
      pk = cryptico.publicKeyFromString(publickey)
      keys[cryptico.publicKeyID(publickey)]=cryptico.b16to64(pk.encrypt(cryptico.bytes2string(aeskey)))
    catch err
      return {success: false, status: "Invalid public key"}
  cipher = cryptico.encryptAESCBC(plaintext, aeskey)
  signature = cryptico.b16to64(key.signString(JSON.stringify(keys) + cipher, "sha256"))
  success: true, packet: JSON.stringify({keys: keys, signature: signature, length: cipher.length}) + "\n" + cipher

decrypt= (key, id, packet)->
  header_length = packet.indexOf("\n")
  header = JSON.parse(packet.slice(0,header_length))
  cipher = packet.slice(header_length+1)
  # todo verify signature
  keyblock = header.keys[id]
  if keyblock
    aeskeytext = key.decrypt(cryptico.b64to16(keyblock))
  else
    throw "Unable to find keyblock!" #TODO get rid of throw!
  if aeskeytext
    plaintext=cryptico.decryptAESCBC(cipher, cryptico.string2bytes(aeskeytext))
    log("decrypt: plaintext=#{plaintext}")
    plaintext
  else
    throw "Unable to decrypt aes key"
