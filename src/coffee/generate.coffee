importScripts('cryptico.js')
self.onmessage = (event)->
  data = event.data
  self.postMessage cryptico.privateKeyString cryptico.generateRSAKey(data.passphrase, data.bits)

