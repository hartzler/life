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
  constructor: (@id, @from, @to, @content, @date, num_likes, comments=[], @links=[]) ->
    @num_likes = ko.observable(num_likes)
    @humaneDate = ko.computed(=>humaneDate(@date))
    @show_comments = ko.observable(false)
    @commentContent = ko.observable("")
    @comments = ko.observableArray(comments)
    @num_comments = ko.computed(=>@comments().length)

  toggle_comments: ->
    @show_comments(!@show_comments())

class Comment
  constructor: (@id, @from, @content, @date)->
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
  constructor: (@callbacks={}) ->

    # visible
    @posts = ko.observableArray([])
    @feed = ko.computed ()=>@posts.sort((a,b)->a.date<b.date).slice(0,20)
      
    @circles = ko.observableArray([])
    @profiles = ko.observableArray([])

    # state
    @state = new State(["not_connected","generating","connecting","connected"])
    @share_state = new State(["mini","max"])
    @to_state = new State(["select","add"])

    # update
    @updateTo = ko.observable()
    @updateContent = ko.observable()
    @updateName = ko.observable()
    @updateEmail = ko.observable()

    # setup
    @email = ko.observable("")
    @password = ko.observable("")
    @remember = ko.observable(false)

  updateToggleTo: ->
    @updateTo(true)

  updateReset: ->
    # reset form, can i just form reset?
    @updateTo(null)
    @updateContent("")
    @updateName(null)
    @updateEmail(null)
    @share_state.set_mini()

  update: ->
    # create new post
    @callbacks.post(@updateTo(),@updateName(),@updateEmail(),@updateContent())

  connect: ->
    @state.set_connecting()
    @callbacks.connect(@email(), @password(), @remember())

  like: (post)->
    @callbacks.like(post)

  submitComment: (post)->
    @callbacks.comment(post,post.commentContent())
    post.commentContent("")

# exports
window.ViewModel = ViewModel
window.Profile = Profile
window.Circle = Circle
window.Post = Post
window.Comment = Comment
