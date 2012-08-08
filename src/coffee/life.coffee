logger = new Util.Logger('Life::Controller','debug')
logger.debug("loading life.js...")

# app settings
clear_cache = false
app_store = new AppStorage()

# crypto
crypto = new Crypto()

# the user profile
me = {}

# our encrypted serialization functions...
decode=(base64)->JSON.parse(crypto.decrypt(JSON.parse(atob(base64))))
encode=(obj,pubkeys)->btoa(JSON.stringify(crypto.encrypt(JSON.stringify(obj),pubkeys||[me.pubkey])))

# hook up storage / event handlers
#email_client = new LifeClient()
#email_client.logger = new Util.Logger("Life::Storage::EmailClient",'debug')
email_client = {}
email_client.logger = new Util.Logger("Life::Storage::TestEmailClient",'debug')
email_client.send= (msg,rest...)->@logger.debug("send: #{msg.toSource()}"); @notify(msg)
email_client.connect= (options)->@options=options; @logger.debug("connect: #{options.toSource()}"); on_connect()
bus= new EmailBus(email_client)
ls =
  get: (id)->app_store.get_object(id)
  put: (obj)->app_store.put_object(obj)
  list: (options)->app_store.list_objects(options)
rs = new EmailSync(bus,((obj)->(encode(obj,[me.pubkey]))),decode)
storage = new Storage(ls,rs)

on_connect = ()->
  # make sure we have a me object...
  me = (p for p in list_profiles() when p.email is viewModel.email())[0]
  if !me
    logger.debug("no me profile found, creating one...")
    me = pubkey: crypto.public_key(), display:"Me", email:viewModel.email() # hack for now... as can cause duplicate when restoring from email...
    store_profile(me)
  
  logger.debug("me: #{me.toSource()}")

  # sync to view model
  loadViewModel()
  viewModel.state.set_connected()
  
# handle new objects from remote...
storage.on_obj = (obj)->
  logger.debug("sync obj from storage: #{obj.toSource()}")
  switch obj.tag
    when "circle" then replace_in_observable_array(viewModel.circles, circle2view(obj))
    when "profile" then replace_in_observable_array(viewModel.profiles, profile2view(obj))
    when "post" then replace_in_observable_array(viewModel.posts, post2view(obj))
    when "comment" then #
    when "like" then #

# Setup ViewModel / event handlers
viewModel=new ViewModel(
  comment: (post, content)->
    outgoing.comment(post,content)

  like: (post)->
    logger.debug("ViewModel called like callback!")
    if storage.list(tag:"like",parent_id:post.id,from_id:me.id).length < 1
      outgoing.like(post)

  post: (to,name,email,content)->
    if email
      to = store_profile(display:name, email:email)
    post = id:Util.uuid(), from: me.id, to: [to.id], content: content
    if to.pubkey?
      outgoing.post(post)
    else
      store_queued(post)
      outgoing.ake(to)
    viewModel.updateReset()

  connect: (email,password,remember)->
    app_store.put('email', email)
    if remember
      app_store.put('password', password)
    else
      app_store.put('password', null)
    email_client.connect(email:email,password:password,imap_server:"imap.gmail.com",smtp_server:"smtp.gmail.com",clear_cache:clear_cache,logging:true,
      on_connect,
      ((err)->),
      (()->),
    )
)

viewModel.email(app_store.get('email'))
p=app_store.get('password')
viewModel.password(p)
viewModel.remember(p?)

# key
key = app_store.get('key')
if key
  crypto.setkey key
else
  viewModel.state.set_generating()
  crypto.generate ()->
    app_store.put('key',crypto.private_key())
    viewModel.state.set_not_connected()

# model->view Helpers
profile2view = (model)->
  new Profile(model.id,model.display,model.email,model.pubkey)

circle2view = (model)->
  new Circle(model.id,model.name,profile2view(get_profile(p)) for p in model.profiles)

post2view = (model)->
  num_comments = storage.list(tag:"comment",parent_id:model.id).length
  num_likes = storage.list(tag:"like",parent_id:model.id).length
  new Post model.id,
    profile2view(get_profile(model.from)),
    (profile2view(get_profile(p)) for p in model.to),
    model.content,new Date(model.date),
    num_comments,
    num_likes

replace_in_observable_array = (array,obj)->
  if existing = (vm for vm in array() when vm.id is obj.id)[0]
    logger.debug("collection: replace #{existing.toSource()} with #{obj.toSource()}")
    array.splice(array.indexOf(existing),1,obj)
  else
    logger.debug("collection: pushing #{obj.toSource()}")
    array.push(obj)

loadViewModel = ()->
  viewModel.profiles(profile2view(p) for p in list_profiles())
  viewModel.circles(circle2view(c) for c in list_circles())
  viewModel.posts(post2view(p) for p in list_posts())
  logger.debug("view posts: " + ko.toJS(viewModel.posts).toSource())


# Storage helpers
get_profile_by_email = (email)->
  (p for p in list_profiles() when p.email is email)[0]

get_post= (id)-> storage.get(id)
get_circle= (id)-> storage.get(id)
get_profile= (id)-> storage.get(id)
list_circles= -> storage.list(tag:"circle")
list_profiles= -> storage.list(tag:"profile",limit:1000)
list_posts= -> storage.list(tag:"post")
list_queued= -> storage.list(tag:"queued")

store=(obj,tag,local_only)->
   obj.id||=Util.uuid()
   obj.tag=tag
   obj.date||=new Date().getTime()
   logger.debug("storing object: #{obj.toSource()}")
   storage.put(obj,local_only)
   obj

store_circle= (obj)->
  store(obj,"circle")
  replace_in_observable_array(viewModel.circles, circle2view(obj))
  obj

store_profile= (obj)->
  obj.display ||= obj.email
  store(obj,"profile")
  replace_in_observable_array(viewModel.profiles,profile2view(obj))
  obj

store_post= (obj)->
  store(obj,"post")
  replace_in_observable_array(viewModel.posts, post2view(obj))
  obj

store_queued= (obj)->
  store(obj, "queued",true)
  replace_in_observable_array(viewModel.posts, post2view(obj))

store_like= (obj)->
  store(obj, "like")
  #view = (p for p in viewModel.posts() when p.id is obj.parent_id)[0]
  #view.num_likes() if(p)
  replace_in_observable_array(viewModel.posts, post2view(get_profile(obj.parent_id)))
  obj

store_comment= (obj)->
  store(obj, "comment")
  replace_in_observable_array(viewModel.posts, post2view(get_profile(obj.parent_id)))
  obj

remote_post_profile= (profile)->
  pubkey: profile.pubkey, email: profile.email


send_queued= (p)->
  logger.debug("sending queued posts for: #{p.toSource()}")
  store_post(stored) for stored in list_queued() when stored.to.indexOf(p.id) isnt -1

send= (obj, tos)->
  try
    bus.send(
      to:(p.email for p in tos)
      subject: "Private Message"
      tag:obj.tag
      crypted: true
      base64: encode(obj,(p.pubkey for p in tos))
    )
  catch e
    logger.error("error sending out message on bus!  #{obj.toSource()}",e)
    

# Send messages over the bus
outgoing=
  post: (post)->
    logger.debug("sending post w/ content #{post.content}")
    local=store_post(post)
    profiles=(get_profile(pid) for pid in local.to)
    local.from = {email:me.email}
    local.to = (email:p.email for p in profiles)
    send(local, profiles)

  like: (post)->
    logger.debug("sending like for post: #{post.id}")
    local=store(from:me.id, parent_id:post.id, "like")
    local.from = {email:me.email}
    send(local,post.to)

  comment: (post,content)->
    logger.debug("sending comment for post: #{get_post(post.id).toSource()} w/ content #{content}")
    local=store(from:me.id, parent_id:post.id, content:content, "comment")
    local.from = {email:me.email}
    send(local,post.to)

  ake: (to)->
    email_client.send(
      to:[to.email]
      subject:"Friend Request"
      crypted: false
      tag: "ake"
      base64:atob(JSON.stringify(email:me.email, pubkey:me.pubkey, tag:"ake"))
      txt:"Download the Life client to see the message: http://173.29.20.141:3366/"
    )

  ake_response: (to)->
    send(tag:"ake_response", email: me.email, pubkey: me.pubkey, [to])


get_or_create_profile_by_email= (p)->
  unless p=get_profile_by_email(p.email)
    p=store_profile(p)
  return p

remote2local= (obj)->
  obj.from = get_or_create_profile_by_email(obj.from).id if obj.from?
  obj.to = (get_or_create_profile_by_email(email).id for email in obj.to) if obj.to?
  obj

local2remote= (obj)->
  obj.from = email:get_profile(obj.from).id if obj.from?
  obj.to = (email:p.email for p in (get_profile(pid) for email in obj.to)) if obj.to?
  obj
   

# handle incoming messages from the bus
incoming=
  post: (obj)->
    store_post(remote2local(obj))
  like: (obj)->
    store_like(remote2local(obj))
  comment: (obj)->
    store_comment(remote2local(obj))

  # handle key exchange message
  ake: (obj)->
    logger.debug("received ake: #{obj.toSource()}")
    p=get_profile_by_email(obj.email)
    if p?
      # TODO: SECURITY: risk here of blindly updating pubkey!  probably need to prompt user...
      p.pubkey = obj.pubkey
    else
      p = email: obj.email, pubkey: obj.pubkey, display: obj.display
    store_profile(p)
    outgoing.ake_response(p)

  # send any queued messages!
  ake_response: (obj)->
    p=get_profile_by_email(obj.email)
    if p?
      p.pubkey = obj.pubkey
      store_profile(p)
      send_queued(p)
    else
      logger.error("DISCARDING ake response: not expecting ake response: #{obj.toSource()}")

bus.on 'receive', (base64,subject)->
  logger.debug("received msg on bus w/ subject: #{subject}")
  switch(subject)
    when 'Private Message'
      obj = decode(base64)
      logger.debug("received private message on bus: #{obj.toSource()}")
      incoming[obj.tag](obj)
    when 'Friend Request'
      incoming.ake(JSON.parse(btoa(base64)))

window.onerror = (event)->
  logger.error("Unhandled error in window! #{event.toSource()}")

# don't like this here...
# Setup KO bindings
$(document).ready ->
  ko.applyBindings(viewModel)

