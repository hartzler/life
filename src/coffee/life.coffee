logger = new Util.Logger('Life::Controller','debug')
logger.debug("loading life.js...")

# app settings
clear_cache = false
app_store = new AppStorage()

# crypto
crypto = new Crypto()

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
 
  # test data...
  #storage.on_receive(id:Util.uuid(),tag:"post",content:"WHATUP",date:"",from:{email:"tool@you.com"},to:[email:me.email],date:new Date().getTime())
  
# handle new objects from remote...
storage.on_receive = (obj)->
  switch obj.tag
    when "circle" then store_circle(obj)
    when "profile" then store_profile(obj)
    when "post" then store_post(obj,true)

# Setup ViewModel / event handlers
viewModel=new ViewModel(
  update: (to,name,email,content)->
    if email
      to = store_profile(display:name, email:email)
    store_post(id:Util.uuid(), from: me.id, to: [to.id], content: content, date:new Date().getTime())
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
  crypto.key = JSON.parse(key)
else
  viewModel.state.set_generating()
  #crypto.generate((key)->
  worker = new Worker('chrome://life/content/javascript/generate.js')
  worker.onmessage = (event)->
    crypto.key = event.data
    logger.debug("strong private key...")
    app_store.put('key',JSON.stringify(crypto.key))
    viewModel.state.set_not_connected()
  worker.postMessage(passphrase: Util.uuid()+Util.uuid()+(new Date().getTime()), bits: 1024)

# Helpers
profile2view = (model)->
  new Profile(model.id,model.display,model.email)

circle2view = (model)->
  new Circle(model.id,model.name,profile2view(get_profile(p)) for p in model.profiles)

post2view = (model)->
  new Post(model.id,profile2view(get_profile(model.from)),(profile2view(get_profile(p)) for p in model.to),model.content,new Date(model.date))

replace_in_observable_array = (array,obj)->
  if existing = (vm for vm in array when vm.id is obj.id)[0]
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

store=(obj,tag,local_only)->
   obj.id||=Util.uuid()
   obj.tag=tag
   logger.debug("storing object: #{obj.toSource()}")
   storage.put(obj,local_only)

store_circle= (obj)->
  store(obj,"circle",true)
  replace_in_observable_array(viewModel.circles, circle2view(obj))
  obj

store_profile= (obj)->
  store(obj,"profile",true)
  replace_in_observable_array(viewModel.profiles,profile2view(obj))
  obj

store_post= (obj,local_only)->
  store(obj,"post",local_only)
  replace_in_observable_array(viewModel.posts, post2view(obj))
  obj

remote_post_profile= (profile)->
  email: profile.email

stringy= (obj)->
  crypto.encrypt(JSON.stringify(local2remote(obj)),(if obj.tag is "post" then (get_profile(p).pubkey for p in obj.to) else [me.pubkey]))

objify= (str)->
  remote2local(JSON.parse(crypto.decrypt(str)))

tos= (obj)->
  if obj.tag is "post" then (p.email for p in obj.to) else [me.email])

remote2local = (obj)->
  if obj.tag is "post"
    profiles = [].concat(obj.to)
    profiles.push(obj.from)
    logger.debug("checking for profiles to create in #{profiles.toSource()}")
    for p in profiles
      if !get_profile_by_email(p.email)
        logger.debug("creating profile from email=#{p.email} for post=#{obj.toSource()}")
        newp = display:p.email, email:p.email
        store_profile(newp)

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

# don't like this here...
# Setup KO bindings
$(document).ready ->
  ko.applyBindings(viewModel)

