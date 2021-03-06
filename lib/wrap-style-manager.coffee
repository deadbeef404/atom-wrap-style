{CompositeDisposable} = require 'atom'
DisplayBuffer = require atom.packages.resourcePathWithTrailingSlash + 'src/display-buffer'
TokenizedLine = require atom.packages.resourcePathWithTrailingSlash + 'src/tokenized-line'
React = require 'react'
ReactDom = require 'react-dom'
WrapStyleSandbox = require './wrap-style-sandbox'

module.exports =
class WrapStyleManager
  @defaultFontFamily = "Menlo, Consolas, 'DejaVu Sans Mono', monospace"

  constructor: ->
    @originalFindWrapColumn = null
    @sandbox = null
    @memoryMap = new Map

    # Create root element
    @element = document.createElement 'div'
    @element.classList.add 'wrap-style'
    @element.style.position = 'absolute'
    @element.style.visibility = 'hidden'
    atom.views.getView atom.workspace
      .appendChild @element

    # Create shadow DOM
    @shadowRoot = @element.createShadowRoot()

    # Set style
    @shadowRoot.appendChild document.createElement 'style'
    @shadowStyle = @shadowRoot.styleSheets[0]
    @shadowStyle.insertRule '.wrap-style-sandbox {}', 0
    @shadowStyleRule = @shadowStyle.cssRules[0]

    # Add top element
    @shadowTop = document.createElement 'div'
    @shadowTop.classList.add 'wrap-style-top'
    @shadowRoot.appendChild @shadowTop

    # add ovserver
    @subscriptions = new CompositeDisposable
    [
      'editor.fontSize'
      'editor.fontFamily'
      'wrap-style.style.whiteSpace'
      'wrap-style.style.lineBreak'
      'wrap-style.style.wordBreak'
      # 'wrap-style.style.hyphens'
      'wrap-style.style.overflowWrap'
      # 'wrap-style.lang'
      'wrap-style.strictMode'
    ].forEach (name) =>
      @subscriptions.add atom.config.observe name, (value) =>
        @renderSandbox()
    @subscriptions.add atom.workspace.observeActivePaneItem (item) =>
      @clearMemory()

    @renderSandbox()

    @subscriptions.add atom.commands.add 'atom-workspace', 'wrap-style:toggle': => @toggle()
    @subscriptions.add atom.config.observe 'wrap-style.enabled', (value) => @setFindWrapColumn(value)
    @setFindWrapColumn atom.config.get 'wrap-style.enabled'

  # Tear down any state and detach
  destroy: ->
    @subscriptions?.dispose()
    @restoreFindWrapColumn()
    @clearMemory()
    ReactDom.unmountComponentAtNode @element
    @element.remove()

  renderSandbox: ->
    style = @shadowStyleRule.style
    style.fontSize = "#{atom.config.get 'editor.fontSize'}px"
    fontFamily = atom.config.get 'editor.fontFamily'
    if fontFamily.length == 0
      fontFamily = WrapStyleManager.defaultFontFamily
    style.fontFamily = fontFamily
    style.whiteSpace = atom.config.get 'wrap-style.style.whiteSpace'
    # style.lineBreak = atom.config.get 'wrap-style.style.lineBreak'
    style.WebkitLineBreak = atom.config.get 'wrap-style.style.lineBreak'
    style.wordBreak = atom.config.get 'wrap-style.style.wordBreak'
    # style.hyphens = atom.config.get 'wrap-style.style.hyphens'
    # style.WebKitHyphens = atom.config.get 'wrap-style.style.hyphens'
    style.overflowWrap = atom.config.get 'wrap-style.style.overflowWrap'
    # @shadowTop.lang = atom.config.get 'wrap-style.lang'
    wrapStyleSandboxElement = React.createElement WrapStyleSandbox,
      strict: atom.config.get 'wrap-style.strictMode'
    @sandbox = ReactDom.render wrapStyleSandboxElement, @shadowTop
    @sandbox.initializeDefaultCharWidth()
    @updateTextEditors()

  # overwrite TokenizedLine#findWrapColumn()
  overwriteFindWrapColumn: ->
    unless @originalFindWrapColumn
      @originalGetSoftWrapColumnForTokenizedLine = DisplayBuffer::getSoftWrapColumnForTokenizedLine
      @originalFindWrapColumn = TokenizedLine::findWrapColumn
      _wrapStyleManager = @
      DisplayBuffer::getSoftWrapColumnForTokenizedLine = DisplayBuffer::getSoftWrapColumn
      TokenizedLine::findWrapColumn = (maxColumn) ->
        # If all characters are full width, the width is twice the length.
        return unless (@text.length * 2) > maxColumn
        return _wrapStyleManager.findWrapColumn(@text, maxColumn)
      @updateTextEditors()

  # restore TokenizedLine#findWrapColumn()
  restoreFindWrapColumn: ->
    if @originalFindWrapColumn
      TokenizedLine::findWrapColumn = @originalFindWrapColumn
      DisplayBuffer::getSoftWrapColumnForTokenizedLine = @originalGetSoftWrapColumnForTokenizedLine
      @originalFindWrapColumn = null
      @originalGetSoftWrapColumnForTokenizedLine = null
      @updateTextEditors()

  setFindWrapColumn: (overwrite) ->
    if overwrite
      @overwriteFindWrapColumn()
    else
      @restoreFindWrapColumn()

  clearMemory: ->
    @memoryMap.clear()

  # another findWrapColumn
  findWrapColumn: (text, column) ->
    key = "#{column}:#{text}"
    if @memoryMap.has key
      return @memoryMap.get key

    breakPointList = @sandbox.calculate column, text
    pre = 0
    for i in breakPointList
      @memoryMap.set "#{column}:#{text.substr(pre)}", i - pre
      pre = i
    @memoryMap.set "#{column}:#{text.substr(pre)}", null
    # console.log @memoryMap
    breakPointList[0]

  toggle: ->
    if atom.config.get 'wrap-style.enabled'
      console.log 'Wrap Style disabled'
      atom.config.set 'wrap-style.enabled', false
    else
      console.log 'Wrap Style enabeld'
      atom.config.set 'wrap-style.enabled', true

  updateTextEditors: ->
    for editor in atom.workspace.getTextEditors()
      editor.displayBuffer.updateWrappedScreenLines()
