importScripts('cryptico-min.js')
self.onmessage = (event)->
  data = event.data
  self.postMessage cryptico.generateRSAKey(data.passphrase, data.bits)

