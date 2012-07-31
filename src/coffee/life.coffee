logger = new Util.Logger('Life::Controller','debug')
logger.debug("loading life.js...")

# app settings
clear_cache = false
app_store = new AppStorage()

# crypto
crypto = new Crypto()

# needed functions to pass to constructors...
remote2local = (obj)->
  logger.debug("received: #{obj.toSource()}")
  if obj.tag is "post"
    profiles = [].concat(obj.to)
    profiles.push(obj.from)
    logger.debug("checking for profiles to create in #{profiles.toSource()}")
    for p in profiles
      if l = get_profile_by_email(p.email)
        # TODO: SECURITY: flaw!!  Need to ask user... or somethign.
        # update pubkeys
        if p.pubkey isnt l.pubkey
          l.pubkey = p.pubkey
          store_profile(p)
      else
        logger.debug("creating profile from email=#{p.email} for post=#{obj.toSource()}")
        store_profile(p)

    # transform remote to/from to ids
    obj.to = (get_profile_by_email(p.email).id for p in obj.to)
    obj.from = get_profile_by_email(obj.from.email).id
    obj
  else
    obj

local2remote = (obj)->
  if obj.tag is "post"
    r = deep_copy(obj)
    r.to = (remote_post_profile(get_profile(p)) for p in obj.to) # array of ids to array of remote profile objs
    r.from = (remote_post_profile(get_profile(obj.from))) # id to remote profile obj
    r
  else
    obj

stringify= (obj)->
  switch obj.tag
    when "ake"
      btoa(JSON.stringify(obj))
    when "ake_response"
      crypto.encrypt JSON.stringify(local2remote(obj)), [obj.to]
    when "post"
      crypto.encrypt JSON.stringify(local2remote(obj)), (get_profile(p).pubkey for p in obj.to)
    else
      crypto.encrypt JSON.stringify(local2remote(obj)), [me.pubkey]

objify= (tag,str)->
  switch tag
    when "ake"
      JSON.parse(atob(str))
    else
      remote2local(JSON.parse(crypto.decrypt(str)))

tos= (obj)->
  switch obj.tag
    when "post"
      (get_profile(pid).email for pid in obj.to)
    else
      [me.email]


# hook up storage / event handlers
ls =
  get: (id)->app_store.get_object(id)
  put: (obj)->app_store.put_object(obj)
  list: (tag)->app_store.list_objects(tag)
rs = new EmailRemoteStorage(stringify, objify, tos)
storage = new Storage(ls,rs)
me = {}

storage.on_connect = ()->
  # make sure we have a me object...
  me = (p for p in list_profiles() when p.email is viewModel.email())[0]
  if !me
    me = pubkey: crypto.public_key(), display:"Me", email:viewModel.email() # hack for now... as can cause duplicate when restoring from email...
    store_profile(me)
  
  logger.debug("me: #{me.toSource()}")

  # sync to view model
  loadViewModel()
  viewModel.state.set_connected()
  
# handle new objects from remote...
storage.on_receive = (obj)->
  switch obj.tag
    when "circle" then store_circle(obj,true)
    when "profile" then store_profile(obj,true)
    when "post" then store_post(obj,true)
    when "ake" then on_ake(obj)
    when "ake_response" then on_ake_response(obj)

# Setup ViewModel / event handlers
viewModel=new ViewModel(
  update: (to,name,email,content)->
    if email
      to = store_profile(display:name, email:email)
    post = id:Util.uuid(), from: me.id, to: [to.id], content: content, date:new Date().getTime()
    if to.pubkey?
      store_post(post)
    else
      store_queued(post)
      send_ake(to)
    viewModel.updateReset()
  connect: (email,password,remember)->
    app_store.put('email', email)
    if remember
      app_store.put('password', password)
    else
      app_store.put('password', null)
    storage.connect(email:email,password:password,imap_server:"imap.gmail.com",smtp_server:"smtp.gmail.com",clear_cache:clear_cache,logging:true)
  )

viewModel.email(app_store.get('email'))
p=app_store.get('password')
viewModel.password(p)
viewModel.remember(p?)

# key
key = app_store.get('key')
if key
  logger.debug("setting private key: #{key}")
  crypto.setkey key
else
  viewModel.state.set_generating()
  crypto.generate ()->
    logger.debug("storing private key: #{crypto.private_key()}")
    app_store.put('key',crypto.private_key())
    viewModel.state.set_not_connected()

# Helpers
profile2view = (model)->
  new Profile(model.id,model.display,model.email,model.pubkey)

circle2view = (model)->
  new Circle(model.id,model.name,profile2view(get_profile(p)) for p in model.profiles)

post2view = (model)->
  new Post(model.id,profile2view(get_profile(model.from)),(profile2view(get_profile(p)) for p in model.to),model.content,new Date(model.date))

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

get_profile_by_email = (email)->
  (p for p in list_profiles() when p.email is email)[0]

get_post= (id)-> storage.get(id)
get_circle= (id)-> storage.get(id)
get_profile= (id)->
  if typeof id == "object"
    get_profile_by_email(id.email)
  else
    storage.get(id)

list_circles= -> storage.list("circle")
list_profiles= -> storage.list("profile")
list_posts= -> storage.list("post")
list_queued= -> storage.list("queued")

store=(obj,tag,local_only)->
   obj.id||=Util.uuid()
   obj.tag=tag
   logger.debug("storing object: #{obj.toSource()}")
   storage.put(obj,local_only)

store_circle= (obj,local_only)->
  store(obj,"circle",local_only)
  replace_in_observable_array(viewModel.circles, circle2view(obj))
  obj

store_profile= (obj,local_only)->
  obj.display ||= obj.email
  store(obj,"profile",local_only)
  replace_in_observable_array(viewModel.profiles,profile2view(obj))
  obj

store_post= (obj,local_only)->
  store(obj,"post",local_only)
  replace_in_observable_array(viewModel.posts, post2view(obj))
  obj

store_queued= (obj)->
  store(obj, "queued", true)
  replace_in_observable_array(viewModel.posts, post2view(obj))

remote_post_profile= (profile)->
  pubkey: profile.pubkey, email: profile.email

send_ake= (to)->
  storage.remote.send_impl {email:me.email, pubkey:me.pubkey, tag:"ake"},
    [to.email],
    subject:"You have a new private message!",txt:"Download the Life client to see the message: http://173.29.20.141:3366/"

send_ake_response= (to)->
  storage.remote.send_impl {tag:"ake_response", email: me.email, pubkey: me.pubkey, to: to.pubkey},
    [to.email],
    {}

send_queued= (p)->
  logger.debug("sending queued posts for: #{p.toSource()}")
  store_post(stored) for stored in list_queued() when stored.to.indexOf(p.id) isnt -1

# handle key exchange message
on_ake= (obj)->
  logger.debug("received ake: #{obj.toSource()}")
  p=get_profile_by_email(obj.email)
  if p?
    # TODO: SECURITY: risk here of blindly updating pubkey!  probably need to prompt user...
    p.pubkey = obj.pubkey
  else
    p = email: obj.email, pubkey: obj.pubkey, display: obj.display
  store_profile(p)
  send_ake_response(p)

# send any queued messages!
on_ake_response= (obj)->
  p=get_profile_by_email(obj.email)
  if p?
    p.pubkey = obj.pubkey
    store_profile(p)
    send_queued(p)
  else
    logger.error("DISCARDING ake response: not expecting ake response: #{obj.toSource()}")


# don't like this here...
# Setup KO bindings
$(document).ready ->
  ko.applyBindings(viewModel)

