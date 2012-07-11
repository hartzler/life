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
    @posts = ko.observableArray(posts)
    @circles = ko.observableArray(circles)
    @profiles = ko.observableArray(profiles)
    @callbacks = callbacks
    @updateTo = ko.observable()
    @updateContent = ko.observable()

  update: ->
    # create new post
    @callbacks.update(@updateTo(),@updateContent())

  updateReset: ->
    # reset form
    @updateTo(null)
    @updateContent(null)

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
    @user = id:1, display:"Me", atts:{email: "matt.hartzler@gmail.com"}

    @store_profile(profile) for profile in [
      @user,
      {id:2, display:"Marcus Maday", atts:{email: "marcus.maday@gmail.com"}},
      {id:3, display:"Josh Sommer", atts:{email: "josh.sommer@gmail.com"}},
      {id:4, display:"Jes Hartzler", atts:{email: "jeshartzler@gmail.com"}},
      {id:5, display:"Todd Hartzler", atts:{email: "thartzler@technologist.com"}},
    ]

    @store_circle(circle) for circle in [
      {id:1, name:"All", profiles:[1,2,3,4,5]},
      {id:2, name:"Friends", profiles:[2,3]},
      {id:3, name:"Family", profiles:[4,5]},
    ]
 
    @store_post(post) for post in [
      {id:1, from:2, to:[1], content:"Hi there buddy!", date:new Date()},
      {id:2, from:1, to:[2,3], content:"I love you guys!", date:new Date()},
      {id:3, from:4, to:[1,5], content:"I'm eating...  Yum.", date:new Date()},
    ]

  load_circles: (filter)-> circle for id,circle of @circles
  store_circle: (circle)-> @circles[circle.id]=circle
  remove_circle: (circle)-> delete @circles[circle.id]

  user: -> @user
  load_profiles: (filter)-> profile for id,profile of @profiles
  store_profile: (profile)-> @profiles[profile.id] = profile
  remove_profile: (profile)-> delete @profiles[profile.id]

  load_posts: (filter)-> post for id,post of @posts
  store_post: (post)-> @posts[post.id]=post

profile2view = (model)->new Profile(model.id,model.display,model.atts)
circle2view = (model)->new Circle(model.id,model.name,profile2view(storage.profiles[p]) for p in model.profiles)
post2view = (model)->new Post(model.id,profile2view(storage.profiles[model.from]),profile2view(storage.profiles[p]) for p in model.to,model.content,model.date)

# Crypto
class Crypto
  constructor: ()->
  encrypt: (profile,msg)->
  decrypt: (profile,bytes)->

# Transport
class Transport
  constructor: ()->
  send: (msg)->
  receive: (msg)->

# controller
storage = new TestStorage()
crypto = new Crypto()
transport = new Transport()
viewModel = new ViewModel(
  post2view(p) for p in storage.load_posts(),
  circle2view(c) for c in storage.load_circles(),
  profile2view(p) for p in storage.load_profiles(),
  update: (to,content)->
    post = id:new Date().getTime(), from: storage.user.id, to: [to.id], content: content, date:new Date()
    # TODO: send!
    storage.store_post(post)
    viewModel.posts.push(post2view(post))
    viewModel.updateReset()
  )

$(document).ready ->
  $('ul.nav a').click (e)-> e.preventDefault(); $(this).tab('show')
  ko.applyBindings(viewModel)
