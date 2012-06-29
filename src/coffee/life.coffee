class Message
  constructor: (@id, @from, @to, @content, @date) ->

class FeedViewModel
  constructor: (msgs) ->
    @messages = ko.observableArray(msgs)

testData = [
  new Message("1", "jack", "me", "Hi there buddy!", new Date()),
  new Message("2", "jill", "me, jack", "I love you guys!", new Date()),
  new Message("3", "jack", "me, jill", "I'm eating...  Yum.", new Date())
]

viewModel = new FeedViewModel(testData)

$(document).ready ->
  ko.applyBindings(viewModel)
