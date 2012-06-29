class Message
  constructor: (@id, @to, @content, @date) ->

class FeedViewModel
  constructor: (msgs) ->
    @messages = ko.observableArray(msgs)

testData = [
  new Message("1", "me", "Hi there buddy!", new Date()),
  new Message("2", "me, jack", "I love you guys!", new Date()),
  new Message("3", "me, jill", "I'm eating...  Yum.", new Date())
]

viewModel = new FeedViewModel(testData)

$(document).ready ->
  ko.applyBindings(viewModel)
