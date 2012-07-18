logger = new Util.Logger('Life::Controller','debug')
logger.debug("loading...")

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
  constructor: (callbacks={}) ->

    # visible
    @posts = ko.observableArray([])
    @circles = ko.observableArray([])
    @profiles = ko.observableArray([])

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
    @client.logger = new Util.Logger("Life::DataSource",'debug')

  connect: (email,password,imap_server,smtp_server)->
    @client.connect(logging:true,email:email,password:password,imap_server:imap_server,smtp_server:smtp_server, @on_client_success, @on_client_error, @on_client_toggle)

  on_client_success: ()-> logger.debug("client connected...")
  on_client_error: (msg)-> logger.error(msg)
  on_client_toggle: ()-> logger.debug("client toggle...")

  load_circle: (id)-> @client.get(id)
  load_profile: (id)-> @client.get(id)
  load_post: (id)-> @client.get(id)

  list_circles: -> @client.list(undefined,"circle")
  list_profiles: -> @client.list(undefined,"profile")
  list_posts: -> @client.list(undefined,"post")

  store_circle: (m)-> @store("circle",[@email],m)
  store_profile: (m)-> @store("profile",[@email],m)
  store_post: (m)=>
    emails = (@client.get(p).atts.email for p in m.to)
    @store("post",emails,m)

  store: (type,to,m)->
    m.id ||= Util.uuid()
    @client.send type, # tag
      to, # to 
      "Private Message", # subject
      undefined, # related
      undefined, # html
      undefined, # txt
      m, # obj
      ()->logger.debug("store success..."), # success
      (msg)->logger.debug(msg) # failure


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
  if false and storage.list_circles().length < 1
    storage.store_profile(profile) for profile in [
        me=storage.user={display:"Me", atts:{email: email}},
        marcus={display:"Marcus Maday", atts:{email: "marcus.maday@gmail.com"}},
        josh={display:"Josh Sommer", atts:{email: "josh.sommer@gmail.com"}},
        jes={display:"Jes Hartzler", atts:{email: "jeshartzler@gmail.com"}},
        todd={display:"Todd Hartzler", atts:{email: "thartzler@technologist.com"}},
      ]

    storage.store_circle(circle) for circle in [
        all={name:"All", profiles:[me.id,marcus.id,josh.id,jes.id,todd.id]},
        friends={name:"Friends", profiles:[marcus.id,josh.id]},
        family={name:"Family", profiles:[jes.id,todd.id]},
      ]
   
    storage.store_post(post) for post in [
        {from:marcus.id, to:[me.id], content:"Hi there buddy!", date:new Date()},
        {from:me.id, to:[marcus.id,josh.id], content:"I love you guys!", date:new Date()},
        {from:josh.id, to:[me.id,todd.id], content:"I'm eating...  Yum.", date:new Date()},
      ]

  logger.debug("profiles: " + storage.list_profiles().toSource())
  logger.debug("circles: " + storage.list_circles().toSource())

  # load data
  viewModel.profiles(profile2view(storage.load_profile(p)) for p in storage.list_profiles())
  viewModel.circles(circle2view(storage.load_circle(c)) for c in storage.list_circles())
  viewModel.posts(post2view(storage.load_post(p)) for p in storage.list_posts())
  storage.user = p for p in viewModel.profiles() when p.display is "Me"
  

viewModel=new ViewModel(
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

  # bind
  ko.applyBindings(viewModel)

  # connect
  #viewModel.connect()
