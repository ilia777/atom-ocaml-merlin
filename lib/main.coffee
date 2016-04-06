{CompositeDisposable} = require 'atom'

Merlin = null
Buffer = null
TypeView = null

module.exports =
  merlin: null
  subscriptions: null
  buffers: {}

  typeView: null

  occurrences: null

  returnToFile: null
  returnToPoint: null

  selections: null
  selectionIndex: null

  activate: (state) ->
    Merlin = require './merlin'
    Buffer = require './buffer'
    TypeView = require './type-view'

    @merlin = new Merlin

    @subscriptions = new CompositeDisposable

    @subscriptions.add atom.config.onDidChange 'ocaml-merlin.merlinPath', =>
      buffer.setChanged true for _, buffer of @buffers
      @merlin.restart()

    @subscriptions.add atom.config.onDidChange 'ocaml-merlin.merlinArguments',=>
      buffer.setChanged true for _, buffer of @buffers
      @merlin.restart()

    target = 'atom-text-editor[data-grammar="source ocaml"]'
    @subscriptions.add atom.commands.add target,
      'ocaml-merlin:show-type': => @showType()
      'ocaml-merlin:shrink-type': => @typeView?.shrink()
      'ocaml-merlin:expand-type': => @typeView?.expand()
      'ocaml-merlin:close-bubble': => @typeView?.destroy()
      'ocaml-merlin:next-occurrence': => @getOccurrence(1)
      'ocaml-merlin:previous-occurrence': => @getOccurrence(-1)
      'ocaml-merlin:go-to-declaration': => @goToDeclaration('ml')
      'ocaml-merlin:go-to-type-declaration': => @goToDeclaration('mli')
      'ocaml-merlin:return-from-declaration': => @returnFromDeclaration()
      'ocaml-merlin:shrink-selection': => @getSelection(-1)
      'ocaml-merlin:expand-selection': => @getSelection(1)

    @subscriptions.add atom.workspace.observeTextEditors (editor) =>
      @subscriptions.add editor.observeGrammar (grammar) =>
        if grammar.scopeName == 'source.ocaml'
          @addBuffer editor.getBuffer()
        else
          @removeBuffer editor.getBuffer()

  addBuffer: (textBuffer) ->
    bufferId = textBuffer.getId()
    return if @buffers[bufferId]?
    @buffers[bufferId] = new Buffer textBuffer, => delete @buffers[bufferId]

  removeBuffer: (textBuffer) ->
    @buffers[textBuffer.getId()]?.destroy()

  getBuffer: (editor) ->
    @buffers[editor.getBuffer().getId()]

  showType: ->
    return unless editor = atom.workspace.getActiveTextEditor()
    @merlin.type @getBuffer(editor), editor.getCursorBufferPosition()
    .then (typeList) =>
      @typeView?.destroy()
      return unless typeList.length
      @typeView = new TypeView typeList, editor
      @typeView.show()

  getOccurrence: (offset) ->
    return unless editor = atom.workspace.getActiveTextEditor()
    point = editor.getCursorBufferPosition()
    @merlin.occurrences @getBuffer(editor), point
    .then (ranges) ->
      index = ranges.findIndex (range) -> range.containsPoint point
      range = ranges[(index + offset) % ranges.length]
      editor.setSelectedBufferRange range

  goToDeclaration: (kind) ->
    return unless editor = atom.workspace.getActiveTextEditor()
    @returnToFile = editor.getPath()
    @returnToPoint = editor.getCursorBufferPosition()
    @merlin.locate @getBuffer(editor), @returnToPoint, kind
    .then ({file, point}) ->
      if file?
        atom.workspace.open file,
          initialLine: point.row
          initialColumn: point.column
          pending: true
          searchAllPanes: true
      else
        editor.setCursorBufferPosition point
    , (reason) ->
      atom.workspace.notificationManager.addError reason

  returnFromDeclaration: ->
    return unless @returnToFile?
    atom.workspace.open @returnToFile,
      initialLine: @returnToPoint.row
      initialColumn: @returnToPoint.column
      pending: true
      searchAllPanes: true
    @returnToFile = null
    @returnToPoint = null

  getSelection: (change) ->
    return unless editor = atom.workspace.getActiveTextEditor()
    selection = editor.getSelectedBufferRange()
    @merlin.enclosing @getBuffer(editor), editor.getCursorBufferPosition()
    .then (ranges) ->
      index = ranges.findIndex (range) -> range.containsRange selection
      range = if ranges[index].isEqual selection
        ranges[index + change]
      else if change > 0
        ranges[index + change - 1]
      else
        ranges[index + change]
      editor.setSelectedBufferRange range if range?

  deactivate: ->
    @merlin.close()
    @subscriptions.dispose()
    buffer.destroy() for _, buffer of @buffers

  provideAutocomplete: ->
    kindToType =
      "value": "value"
      "variant": "variable"
      "constructor": "function"
      "label": "tag"
      "module": "class"
      "signature": "type"
      "type": "type"
      "method": "method"
      "#": "method"
      "exn": "constant"
      "class": "class"
    selector: '.source.ocaml'
    getSuggestions: ({editor, bufferPosition, prefix}) =>
      @merlin.complete @getBuffer(editor), bufferPosition, prefix
      .then (entries) ->
        entries.map ({name, kind, desc, info}) ->
          text: name
          type: kindToType[kind]
          leftLabel: kind
          rightLabel: desc
          description: if info.length then desc + '\n' + info else desc
    inclusionPriority: 1
    excludeLowerPriority: true

  provideLinter: ->
    name: 'OCaml Merlin'
    grammarScopes: ['source.ocaml']
    scope: 'file'
    lintOnFly: false
    lint: (editor) =>
      @merlin.errors @getBuffer(editor)
      .then (errors) ->
        errors.map ({range, type, message}) ->
          type: if type == 'warning' then 'Warning' else 'Error'
          text: message
          filePath: editor.getPath()
          range: range
          severity: if type == 'warning' then 'warning' else 'error'