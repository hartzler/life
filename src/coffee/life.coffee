logger = new Util.Logger('Life','debug')
logger.debug("loading life.js...")

clear_cache = false
test_mode = false

Controller.callbacks(
  inited: (email,pass,has_key)->
    logger.debug("inited! has_key=#{has_key}")
    viewModel.email(email)
    viewModel.password(pass)
    viewModel.remember(pass?)
    if has_key
      viewModel.state.set_not_connected()
      viewModel.connect(email,pass,pass?) if test_mode && email?
    else
      viewModel.state.set_generate()

  generated: ()->
    viewModel.msg type:"info", title:"Generated Key!", msg: "You have successfully generated the fancy numbers that will ensure your privacy."
    viewModel.state.set_not_connected()

  connected: (profiles, circles, posts, meuri)->
    logger.debug("connected!")
    viewModel.meuri(meuri)
    loadViewModel(profiles,circles,posts)
    viewModel.state.set_connected()

  new: (obj)->
    logger.debug("new! obj=#{obj.toSource()}")
    switch obj.tag
      when "circle" then replace_in_observable_array(viewModel.circles, circle2view(obj))
      when "profile" then replace_in_observable_array(viewModel.profiles, profile2view(obj))
      when "post" then replace_in_observable_array(viewModel.posts, post2view(obj))
      when "comment" then replace_in_observable_array((p for p in viewModel.posts() when p.id is obj.parent_id)[0].comments, comment2view(obj))
      when "like" then replace_in_observable_array((p for p in viewModel.posts() when p.id is obj.parent_id)[0].likes, like2view(obj))
)

# Setup ViewModel / event handlers
viewModel=new ViewModel()
viewModel.callbacks=
  comment: (post, content)->
    Controller.comment post.id, content
    post.commentContent("")

  like: (post)->
    Controller.like post.id

  post: (tos,content)->
    Controller.post (p.id for p in tos), content
    viewModel.updateReset()
    $('ul.nav a[href="#feed"]').tab('show')

  connect: (email,password,remember)->
    viewModel.state.set_connecting()
    Controller.connect remember:remember,email:email,password:password,imap_server:"imap.gmail.com",smtp_server:"smtp.gmail.com",clear_cache:clear_cache,logging:true

  generate: (passphrase)->
    viewModel.state.set_generating()
    Controller.generate(passphrase)

  invite: (email)->
    Controller.invite(email)
    viewModel.invite_email("")

  add_friend: (psnuri)->
    Controller.add_friend(psnuri)

# model->view Helpers
profile2view = (model)->
  new Profile(model.id,model.display,model.email,model.pubkey)

circle2view = (model)->
  new Circle(model.id,model.name,profile2view(get_profile(p)) for p in model.profiles)

post2view = (model)->
  new Post model.id,
    profile2view(get_profile(model.from)),
    (profile2view(get_profile(p)) for p in model.to),
    model.content,new Date(model.date),
    (like2view(l) for l in model.likes||[])
    (comment2view(c) for c in model.comments||[])

comment2view= (c)->
  new Comment(c.id,profile2view(get_profile(c.from)),c.content,new Date(c.date))

like2view= (c)->
  new Like(c.id,profile2view(get_profile(c.from)),new Date(c.date))

get_profile= (pid)->
  (p for p in viewModel.profiles() when p.id is pid)[0]

replace_in_observable_array = (array,obj)->
  if existing = (vm for vm in array() when vm.id is obj.id)[0]
    #logger.debug("collection: replace #{existing.toSource()} with #{obj.toSource()}")
    array.splice(array.indexOf(existing),1,obj)
  else
    #logger.debug("collection: pushing #{obj.toSource()}")
    array.push(obj)

loadViewModel = (profiles,circles,posts)->
  viewModel.profiles(profile2view(p) for p in profiles)
  viewModel.circles(circle2view(c) for c in circles)
  viewModel.posts(post2view(p) for p in posts)
  logger.debug("view posts: " + ko.toJS(viewModel.posts).toSource())

window.onerror = (params...)->
  logger.error("Unhandled error in window! #{params.toSource()}")

# Setup KO bindings
$(document).ready ->
  $('ul.nav a').click (e)-> e.preventDefault(); $(this).tab('show')
  ko.applyBindings(viewModel)

# init background thread
Controller.init()
