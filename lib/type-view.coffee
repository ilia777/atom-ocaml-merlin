module.exports = class TypeView
  @typeList: null
  @typeIndex: 0

  @editor: null
  @marker: null

  @subscription: null

  constructor: (@typeList, @editor) ->
    @typeIndex = 0

  show: ->
    @destroy()
    {range, type} = @typeList[@typeIndex]
    @marker = @editor.markBufferRange range
    @editor.decorateMarker @marker,
      type: 'overlay'
      item: @getBubble type
    @editor.decorateMarker @marker,
      type: 'highlight'
      class: 'ocaml-merlin-highlight'
    @subscription = @editor.onDidChangeCursorPosition => @destroy()

  expand: ->
    return unless @typeIndex + 1 < @typeList?.length ? 0
    @typeIndex += 1
    @show()

  shrink: ->
    return unless @typeindex > 0
    @typeIndex -= 1
    @show()

  getBubble: (type) ->
    bubble = document.createElement 'div'
    bubble.id = 'ocaml-merlin-bubble'
    bubble.className = 'transparent'
    bubble.textContent = type
    bubble.addEventListener 'keydown', ({keyCode}) =>
      @destroy() if keyCode == 27
    bubble

  destroy: ->
    @marker?.destroy()
    @subscription?.dispose()