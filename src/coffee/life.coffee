debug = (s)->
  if s.toSource?
    dump(s.toSource())
  else
    dump(s)
  dump("\n")

# View Model
class Profile
  constructor: (@id, @display, @atts) ->

class Circle
  constructor: (@id, @name, @profiles)->

class Post
  constructor: (@id, @from, @to, @content, @date) ->
    @humaneDate = humaneDate(@date)

# whats visible :)
class ViewModel
  constructor: (posts,circles,profiles,callbacks={}) ->
    debug(posts)
    debug(circles)

    # visible
    @posts = ko.observableArray(posts)
    @circles = ko.observableArray(circles)
    @profiles = ko.observableArray(profiles)

    # update
    @updateTo = ko.observable()
    @updateContent = ko.observable()

    # setup
    @email = ko.observable("deepfall@gmail.com")
    @password = ko.observable("j8d49jqh1")

    @callbacks = callbacks

  update: ->
    # create new post
    @callbacks.update(@updateTo(),@updateContent())

  updateReset: ->
    # reset form
    @updateTo(null)
    @updateContent(null)

  connect: ->
    @callbacks.connect(@email(), @password())

# Storage
class Storage
  constructor: ()->

  circles: (filter)->
  store_circle: (circle)->

  user: ->
  profiles: (filter)->
  store_profile: (profile)->

  posts: (filter)->
  store_post: (post)->

class TestStorage
  constructor: ()->
    @circles = {}
    @profiles = {}
    @posts = {}

  load_circle: (id)->@circles[id]
  list_circles: (filter)-> circle for id,circle of @circles
  store_circle: (circle)-> @circles[circle.id]=circle
  remove_circle: (circle)-> delete @circles[circle.id]

  user: -> @user
  load_profile: (id)->@profiles[id]
  list_profiles: (filter)-> profile for id,profile of @profiles
  store_profile: (profile)-> @profiles[profile.id] = profile
  remove_profile: (profile)-> delete @profiles[profile.id]

  load_post: (id)->@posts[id]
  list_posts: (filter)-> post for id,post of @posts
  store_post: (post)-> @posts[post.id]=post

class ImapStorage
  constructor: (@email)->
    @client = new LifeClient()

  connect: (email,password,imap_server,smtp_server)->
    @client.connect(logging:true,email:email,password:password,imap_server:imap_server,smtp_server:smtp_server, @on_client_success, @on_client_error, @on_client_toggle)

  on_client_success: ()-> debug("client connected...")
  on_client_error: (msg)-> debug(msg)
  on_client_toggle: ()-> debug("client toggle...")

  load_circle: (id)-> @client.get(id)
  load_profile: (id)-> @client.get(id)
  load_post: (id)-> @client.get(id)

  list_circles: -> @client.list(undefined,"circle")
  list_profiles: -> @client.list(undefined,"profile")
  list_posts: -> @client.list(undefined,"post")

  store_circle: (m)-> @client.send("circle",[@email],m)
  store_profile: (m)-> @client.send("profile",[@email],m)
  store_post: (m)-> @client.send("post",(profile2view(p).atts.email for p in m.to),m)

  store: (type,to,m)->
    @client.send
      type, # tag
      to, # to 
      "Private Message", # subject
      undefined, # related
      undefined, # html
      undefined, # txt
      m, # obj
      ()->debug("store success..."), # success
      (msg)->debug(msg) # failure


# storage helper methods
profile2view = (model)->new Profile(model.id,model.display,model.atts)
circle2view = (model)->new Circle(model.id,model.name,profile2view(storage.load_profile(p)) for p in model.profiles)
post2view = (model)->new Post(model.id,profile2view(storage.load_profile(model.from)),profile2view(storage.load_profile(p)) for p in model.to,model.content,model.date)

# Crypto
class Crypto
  constructor: ()->
  encrypt: (profile,msg)->
  decrypt: (profile,bytes)->

# controller
viewModel = null
crypto = new Crypto()
email = "deepfall@gmail.com"
password = "j8d49jqh1"
test_storage = new TestStorage()
storage = new ImapStorage()
storage.on_client_success = ()->
  # insert test data...

  storage.user = id:1, display:"Me", atts:{email: email}

  storage.store_profile(profile) for profile in [
      storage.user,
      {id:2, display:"Marcus Maday", atts:{email: "marcus.maday@gmail.com"}},
      {id:3, display:"Josh Sommer", atts:{email: "josh.sommer@gmail.com"}},
      {id:4, display:"Jes Hartzler", atts:{email: "jeshartzler@gmail.com"}},
      {id:5, display:"Todd Hartzler", atts:{email: "thartzler@technologist.com"}},
    ]

  storage.store_circle(circle) for circle in [
      {id:1, name:"All", profiles:[1,2,3,4,5]},
      {id:2, name:"Friends", profiles:[2,3]},
      {id:3, name:"Family", profiles:[4,5]},
    ]
 
  storage.store_post(post) for post in [
      {id:1, from:2, to:[1], content:"Hi there buddy!", date:new Date()},
      {id:2, from:1, to:[2,3], content:"I love you guys!", date:new Date()},
      {id:3, from:4, to:[1,5], content:"I'm eating...  Yum.", date:new Date()},
    ]

  # load data
  viewModel.profiles(profile2view(p) for p in storage.list_profiles())
  viewModel.circles(circle2view(c) for c in storage.list_circles())
  viewModel.posts(post2view(p) for p in storage.list_posts())
  # bind
  ko.applyBindings(viewModel)

viewModel=new ViewModel([],[],[],
  update: (to,content)->
    post = id:new Date().getTime(), from: storage.user.id, to: [to.id], content: content, date:new Date()
    # TODO: send!
    storage.store_post(post)
    viewModel.posts.push(post2view(post))
    viewModel.updateReset()
  connect: (email,password)->
    storage.email = email
    storage.connect(email,password,"imap.gmail.com","smtp.gmail.com")
  )
# default for now...
viewModel.email(email)
viewModel.password(password)


$(document).ready ->
  $('ul.nav a').click (e)-> e.preventDefault(); $(this).tab('show')

  # connect
  viewModel.connect()
