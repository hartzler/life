logger = new Util.Logger('Life::View','debug')
logger.debug("loading view.js...")

# custom KO handler
ko.bindingHandlers.fadeVisible=
  init: (element, valueAccessor)->
      value = valueAccessor()
      $(element).toggle(ko.utils.unwrapObservable(value))
  update: (element, valueAccessor)->
      value = valueAccessor()
      if ko.utils.unwrapObservable(value) then $(element).fadeIn() else $(element).fadeOut()

ko.bindingHandlers.htmlValue =
  init: (element, valueAccessor, allBindingsAccessor)->
    ko.utils.registerEventHandler element, "blur", ()->
      modelValue = valueAccessor()
      elementValue = Util.sanitize(element.innerHTML)
      if (ko.isWriteableObservable(modelValue))
        modelValue(elementValue)
      else # handle non-observable one-way binding
        allBindings = allBindingsAccessor()
        if allBindings['_ko_property_writers'] && allBindings['_ko_property_writers'].htmlValue
          allBindings['_ko_property_writers'].htmlValue(elementValue)
  update: (element, valueAccessor)->
    value = ko.utils.unwrapObservable(valueAccessor()) || ""
    if element.innerHTML isnt value
      element.innerHTML = Util.sanitize(value)

# View Model
class Profile
  constructor: (@id, @display, @email, @pubkey) ->

class Circle
  constructor: (@id, @name, @profiles)->

class Post
  constructor: (@id, @from, @to, @content, @date, likes=[], comments=[], @links=[]) ->
    @humaneDate = ko.computed(=>humaneDate(@date))
    @show_comments = ko.observable(false)
    @commentContent = ko.observable("")
    @comments = ko.observableArray(comments)
    @num_comments = ko.computed(=>@comments().length)
    @likes = ko.observableArray(likes)
    @num_likes= ko.computed(=>@likes().length)

  toggle_comments: ->
    @show_comments(!@show_comments())

class Comment
  constructor: (@id, @from, @content, @date)->
    @humaneDate = ko.computed(=>humaneDate(@date))

class Like
  constructor: (@id, @from, @date)->
    @humaneDate = ko.computed(=>humaneDate(@date))

class State
  constructor: (states)->
    @state = ko.observable(states[0])
    for state in states
      do (state)=>
        this[state] = ko.computed ()=>@state() is state
        this["set_" + state] = ()=>@state(state)

# whats visible :)
class ViewModel
  constructor: ->

    @msgs = ko.observableArray([])

    @posts = ko.observableArray([])
    @feed = ko.computed ()=>@posts.sort((a,b)->a.date<b.date).slice(0,20)
    @circles = ko.observableArray([])
    @profiles = ko.observableArray([])
    @notifications = ko.observableArray([])

    # friends
    @meuri = ko.observable("")
    @invite_email = ko.observable("")
    @psnuri = ko.observable("")

    # state
    @state = new State(["not_connected","generate","generating","connecting","connected"])
    @share_state = new State(["mini","max"])
    @to_state = new State(["select","add"])

    # post
    @updateContent = ko.observable()
    @updateTo = ko.observable()
    @updateEmailOrUri = ko.observable()
    @updateTos = ko.observableArray([])

    # setup
    @passphrase = ko.observable("")
    @email = ko.observable("")
    @password = ko.observable("")
    @remember = ko.observable(false)

  msg: (m)->
    m.title ||= ""
    @msgs.push(m)

  invite: ->
    @callbacks.invite(@invite_email())
    @msg type:"success", title:"Invited!", msg: "You have successfully sent an invite.  You will soon be the most popular Lifer ever."

  copyuri: ->
    Util.copy_to_clipboard(@meuri())
    @msg type:"info", title:"Copied Life ID!", msg: "Your clipboard is now full of Life!"
    
  updateToggleTo: ->
    @updateTo(true)

  updateReset: ->
    # reset form, can i just form reset?
    @updateTo(null)
    @updateTos([])
    @updateContent("")
    @updateEmailOrUri("")
    @share_state.set_mini()

  updateAddTo: ->
    to=@updateTo()
    if to?
      @updateTos.remove to
      @updateTos.push to
      @updateTo(null)

  updateRemoveTo: (profile)->
    @updateTos.remove(profile)

  update: ->
    # create new post
    @updateAddTo()
    if @updateTos().length <= 0
      @msg type:"error", title:"Error!", msg:"You need to specify a recipient."
    else if @updateContent().length <= 0
      @msg type:"error", title:"Error!", msg:"You need to share something..."
    else
      @callbacks.post(@updateTos(),@updateContent())
      @msg type:"success", title:"Posted!", msg: "You have successfully shared a post.  Well done!"

  close: (msg)->
    @msgs.remove(msg)

  connect: ->
    @callbacks.connect(@email(), @password(), @remember())

  generate: ->
    @callbacks.generate(@passphrase())

  like: (post)->
    @callbacks.like(post)
    @msgs.push type:"success", title:"Liked!", msg: "Everyone likes a liker..."

  submitComment: (post)->
    @callbacks.comment(post,post.commentContent())
    post.commentContent("")
    @msgs.push type:"success", title:"Comment Posted!", msg: "You have an opinion on everything don't you..."

  add_friend: ->
    @callbacks.add_friend(@psnuri())
    @psnuri("")
    @msgs.push type:"success", title:"Friend Added!", msg: "Wow, you sure are popular."

# exports
window.ViewModel = ViewModel
window.Profile = Profile
window.Circle = Circle
window.Post = Post
window.Comment = Comment
window.Like = Like
