logger = new Util.Logger('Life::Controller','debug')
logger.debug("loading background.js...")

# setup DI
app_store = new AppStorage()
crypto = new Crypto()
me = {}

# our async encrypted serialization functions...
decode=(base64,continuation)->crypto.decrypt atob(base64), (plaintext)->continuation(JSON.parse(plaintext))
encode=(obj,pubkeys,continuation)->
  crypto.encrypt JSON.stringify(obj), pubkeys, (result)->
    if result.success
      continuation(btoa(result.packet))
    else
      throw "Error encrypting obj! pubkeys=#{pubkeys.toSource()} result=#{result.toSource()}"

# hook up storage / event handlers
email_client = new LifeClient()
email_client.logger = new Util.Logger("Life::Storage::EmailClient",'debug')
#email_client = {}
#email_client.logger = new Util.Logger("Life::Storage::TestEmailClient",'debug')
#email_client.send= (msg,rest...)->@logger.debug("send: #{msg.toSource()}"); @notify(msg) unless msg.to.indexOf(me.email) > -1
#email_client.connect= (options)->@options=options; @logger.debug("connect: #{options.toSource()}"); handlers.connected(options)
bus= new EmailBus(email_client)
ls =
  get: (id)->app_store.get_object(id)
  put: (obj)->app_store.put_object(obj)
  list: (options)->app_store.list_objects(options)
rs = new EmailSync(bus,((obj,c)->(encode(obj,[me.pubkey],c))),decode)
storage = new Storage(ls,rs)

    
# user initiated tasks
callbacks={}
controller=
  callbacks: (fs)->
    callbacks=fs

  init: ()->
    inited=()->
    if key = app_store.get('key')
      crypto.setkey key
      logger.debug("using key: public=#{crypto.public_key()}")

    callbacks.inited app_store.get('email'), app_store.get('password'), key?

  generate: (passphrase)->
    crypto.generate passphrase, ()->
      logger.debug("generated key: public=#{crypto.public_key()}")
      app_store.put('key',crypto.private_key())
      callbacks.generated()

  connect: (options)->
    app_store.put('email', options.email)
    if options.remember
      app_store.put('password', options.password)
    else
      app_store.put('password', null)

    email_client.connect(options,
      (()->handlers.connected(options)),
      handlers.error,
      handlers.toggle,
    )

  invite: (email)->
    profile=get_or_create_profile_by_email(email:email)
    outgoing.ake(profile)

  add_friend: (psnuri)->
    get_or_create_profile_from_psnuri(psnuri)

  circle: (name,profile_ids)->
    store_circle(name:name, profiles:profile_ids)

  profile: (pubkey, display, email)->
    store_profile(pubkey:pubkey, display:display, email:email)

  post: (to_ids,content)->
    outgoing.post(store_post(from: me.id, to: to_ids, content:content))

  comment: (post_id, content)->
    outgoing.comment(store_comment(from: me.id, parent_id:post_id, content:content))

  like: (post_id)->
    if storage.list(tag:"like",parent_id:post_id,from_id:me.id).length < 1
      outgoing.like(store_like(from:me.id, parent_id:post_id))

# handle events
handlers=
  error: (msg)->logger.error(msg)
  toggle: ()->
  connected: (options)->
    # make sure we have a me object...
    me = (p for p in list_profiles() when p.email is options.email)[0]
    if !me
      logger.debug("no me profile found, creating one...")
      me = pubkey: crypto.public_key(), display:"Me", email:options.email  # hack for now... as can cause duplicate when restoring from email...
      store_profile(me)
    
    logger.debug("me: #{me.toSource()}")
    callbacks.connected list_profiles(), list_circles(), list_posts(), psnuri(me)


###########################
# Storage helpers

psnuri= (p)->"psn2012://#{p.email}/#{p.pubkey}"

parse_psnuri= (uri)->
  match=uri.replace(/\s/,'').match(/psn2012:\/\/(.*?)\/(.*)$/)
  email:match[1],pubkey:match[2]

get_profile_by_email = (email)->
  (p for p in list_profiles() when p.email is email)[0]


add_children_to_post= (post)->
  post.comments = storage.list(tag:"comment",parent_id:post.id)
  post.likes = storage.list(tag:"like",parent_id:post.id)
  post

get_post= (id)->p=storage.get(id)
get_circle= (id)-> storage.get(id)
get_profile= (id)-> storage.get(id)
list_circles= -> storage.list(tag:"circle")
list_profiles= -> storage.list(tag:"profile",limit:1000)
list_posts= ->add_children_to_post(p) for p in storage.list(tag:"post")
list_queued= -> storage.list(tag:"queued")

store=(obj,tag,local_only)->
   obj.id||=Util.uuid()
   obj.tag=tag
   obj.date||=new Date().getTime()
   logger.debug("storing object: #{obj.toSource()}")
   storage.put(obj,local_only)
   # hack!
   if obj.tag is 'post'
     callbacks.new add_children_to_post(get_post(obj.id))
     #callbacks.new obj
   else
     callbacks.new obj
   obj

store_circle= (obj)->
  store(obj,"circle")

store_profile= (obj)->
  obj.display ||= obj.email
  store(obj,"profile")

store_post= (obj)->
  store(obj,"post")

store_queued= (obj)->
  store(obj, "queued",true)

store_like= (obj)->
  store(obj, "like")

store_comment= (obj)->
  store(obj, "comment")

remote_post_profile= (profile)->
  pubkey: profile.pubkey, email: profile.email


######################################################
# BUS

send_queued= (p)->
  logger.debug("sending queued posts for: #{p.toSource()}")
  store_post(stored) for stored in list_queued() when stored.to.indexOf(p.id) isnt -1

send= (obj, tos)->
  local2remote(obj)
  logger.debug("send: obj=#{obj.toSource()} tos=#{tos.toSource()}")
  encode obj,(p.pubkey for p in tos),(base64)->
    logger.debug("sending via bus: #{base64}")
    try
      bus.send(
        to:(p.email for p in tos)
        subject: "Private Message"
        tag:obj.tag
        crypted: true
        base64: base64,
        ((msg)->logger.debug("error sending message via bus: #{msg}"))
      )
    catch e
      logger.error("error sending out message on bus!  #{obj.toSource()}",e)


# Send messages over the bus
outgoing=
  post: (post)->
    tos = (get_profile(pid) for pid in post.to)
    logger.debug("sending post #{post.toSource()}")
    send(post, tos)

  like: (like)->
    logger.debug("sending like: #{like.toSource()}")
    post=get_post(like.parent_id)
    tos = (get_profile(pid) for pid in post.to).concat([get_profile(post.from)])
    send(like,tos)

  comment: (comment)->
    logger.debug("sending comment #{comment.toSource()}")
    post=get_post(comment.parent_id)
    tos = (get_profile(pid) for pid in post.to).concat([get_profile(post.from)])
    send(comment,tos)

  ake: (to)->
    uri = psnuri(me)
    name = me.email
    email_client.send(
      to:[to.email]
      subject:"Friend Request"
      crypted: false
      tag: "ake"
      base64:btoa(JSON.stringify(tag:"ake",psnuri:uri))
      txt:"#{name} would like to share private messages with you using their personal social network.  To receive and share private messages get the Life client:\n\nhttp://173.29.20.141:3366/\n\nCopy and paste the following link after you install the client if you dont see #{name} in your friend list:\n\n#{uri}"
    )

  ake_response: (to)->
    send(tag:"ake_response", psnuri:psnuri(me), [to])

get_or_create_profile_by_email= (p)->
  throw "get_or_create_profile_by_email: missing email in profile: #{p.toSource()}" unless p.email?
  unless pro=get_profile_by_email(p.email)
    pro=store_profile(p)
  return pro

remote2local= (obj)->
  logger.debug("remote2local before: obj=#{obj.toSource()}")
  obj.from = get_or_create_profile_by_email(obj.from).id if obj.from?
  obj.to = (get_or_create_profile_by_email(p).id for p in obj.to) if obj.to?
  logger.debug("remote2local after: obj=#{obj.toSource()}")
  obj

local2remote= (obj)->
  logger.debug("local2remote before: obj=#{obj.toSource()}")
  obj.from = remote_post_profile(get_profile(obj.from)) if obj.from?
  obj.to = (remote_post_profile(p) for p in (get_profile(pid) for pid in obj.to)) if obj.to?
  logger.debug("local2remote after: obj=#{obj.toSource()}")
  obj

get_or_create_profile_from_psnuri= (psnuri)->
  ake_profile = parse_psnuri(psnuri)
  logger.debug("ake profile: #{ake_profile.toSource()}")
  p=get_profile_by_email(ake_profile.email)
  if p?
    # TODO: SECURITY: risk here of blindly updating pubkey!  probably need to prompt user...
    p.pubkey = ake_profile.pubkey
  else
    p = email: ake_profile.email, pubkey: ake_profile.pubkey, display: ake_profile.display
  store_profile(p)

# handle incoming messages from the bus
incoming=
  post: (obj)->store_post(obj)
  like: (obj)->store_like(obj)
  comment: (obj)->store_comment(obj)

  # handle key exchange message
  ake: (obj)->
    logger.debug("received ake: #{obj.toSource()}")
    profile=get_or_create_profile_from_psnuri(obj.psnuri)
    outgoing.ake_response(profile.email) unless profile.email is me.email # don't respond to a malicious ake for ourselves...

  # send any queued messages!
  ake_response: (obj)->
    logger.debug("received ake_response: #{obj.toSource()}")
    p=get_or_create_profile_from_psnuri(obj.psnuri)
    send_queued(p) if p?

bus.on 'receive', (base64,subject)->
  logger.debug("received msg on bus w/ subject: #{subject}")
  switch(subject)
    when 'Private Message'
      decode base64, (obj)->
        logger.debug("received private message on bus: #{obj.toSource()}")
        if incoming[obj.tag]
          incoming[obj.tag](remote2local(obj))
        else
          logger.warn("unknown object of type: #{obj.tag}")
    when 'Friend Request'
      logger.debug("received friend request on bus.")
      incoming.ake(JSON.parse(atob(base64)))

# exports
window.Controller = controller
