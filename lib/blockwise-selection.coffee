{Range} = require 'atom'
_ = require 'underscore-plus'

{sortRanges, getBufferRows} = require './utils'
swrap = require './selection-wrapper'

class BlockwiseSelection
  constructor: (selection) ->
    {@editor} = selection
    @initialize(selection)

  initialize: (selection) ->
    {@goalColumn} = selection.cursor
    @selections = [selection]
    wasReversed = reversed = selection.isReversed()

    # If selection is single line we don't need to add selection.
    # This tweeking allow find-and-replace:select-next then ctrl-v, I(or A) flow work.
    unless swrap(selection).isSingleRow()
      range = selection.getBufferRange()
      if range.end.column is 0
        range.end.row = range.end.row - 1
      if @goalColumn? and not wasReversed
        range.end.column = @goalColumn + 1

      if range.start.column >= range.end.column
        reversed = not reversed
        range = range.translate([0, 1], [0, -1])

      {start, end} = range
      ranges = [start.row..end.row].map (row) ->
        [[row, start.column], [row, end.column]]

      selection.setBufferRange(ranges.shift(), {reversed})
      for range in ranges
        @selections.push(@editor.addSelectionForBufferRange(range, {reversed}))
    @updateProperties()
    @reverse() if wasReversed

  updateProperties: ->
    head = @getHead()
    tail = @getTail()

    for selection in @selections
      swrap(selection).setProperties
        blockwise:
          head: selection is head
          tail: selection is tail

    if @goalColumn?
      for selection in @selections
        selection.cursor.goalColumn = @goalColumn

  isSingleLine: ->
    @selections.length is 1

  getHeight: ->
    [startRow, endRow] = @getBufferRowRange()
    (endRow - startRow) + 1

  getTop: ->
    @selections[0]

  getBottom: ->
    _.last(@selections)

  isReversed: ->
    if @isSingleLine()
      @getTop().isReversed()
    else
      swrap(@getBottom()).isBlockwiseTail()

  getHead: ->
    if @isReversed() then @getTop() else @getBottom()

  getTail: ->
    if @isReversed() then @getBottom() else @getTop()

  reverse: ->
    return if @isSingleLine()
    head = @getHead()
    tail = @getTail()
    swrap(head).setProperties(blockwise: head: false, tail: true)
    swrap(tail).setProperties(blockwise: head: true, tail: false)

  getBufferRowRange: ->
    startRow = @getTop().getBufferRowRange()[0]
    endRow = @getBottom().getBufferRowRange()[0]
    [startRow, endRow]

  setBufferPosition: (point) ->
    head = @getHead()
    @clearSelections(except: head)
    head.cursor.setBufferPosition(point)

  headReversedStateIsInSync: ->
    @isReversed() is @getHead().isReversed()

  setSelectedBufferRanges: (ranges, {reversed}) ->
    sortRanges(ranges)
    range = ranges.shift()
    @setHeadBufferRange(range, {reversed})
    for range in ranges
      @selections.push @editor.addSelectionForBufferRange(range, {reversed})
    @updateProperties()

  setBufferRange: (range) ->
    head = @getHead()
    reversed = if @headReversedStateIsInSync()
      head.isReversed()
    else
      not head.isReversed()
    @setHeadBufferRange(range, {reversed})
    @initialize(head)

  getBufferRange: ->
    start = @getHead().getHeadBufferPosition()
    end = @getTail().getTailBufferPosition()
    if @isReversed()
      end.row += 1 if end.column is 0
    else
      start.row += 1 if start.column is 0

    if @isSingleLine() or @headReversedStateIsInSync()
      new Range(start, end)
    else
      new Range(start, end).translate([0, -1], [0, +1])

  # which must be 'start' or 'end'
  setPositionForSelections: (which) ->
    for selection in @selections
      point = selection.getBufferRange()[which]
      selection.cursor.setBufferPosition(point)

  getGoalColumn: ->
    @goalColumn ? @getHead().getHeadBufferPosition().column

  addSelection: (baseSelection, direction) ->
    {start, end} = baseSelection.getBufferRange()
    _direction = switch direction
      when 'up' then 'previous'
      when 'down' then 'next'
    options = {startRow: end.row, direction: _direction, includeStartRow: false}
    for row in getBufferRows(@editor, options)
      range = [[row, start.column], [row, @getGoalColumn()]]
      unless (clippedRange = @editor.clipBufferRange(range)).isEmpty()
        reversed = @getTail().isReversed()
        return @editor.addSelectionForBufferRange(range, {reversed})
    null

  moveSelection: (direction) ->
    isExpanding = =>
      return true if @isSingleLine()
      switch direction
        when 'down' then not @isReversed()
        when 'up' then @isReversed()

    if isExpanding()
      switch direction
        when 'up'
          if selection = @addSelection(@getTop(), direction)
            @selections.unshift(selection)
        when 'down'
          if selection = @addSelection(@getBottom(), direction)
            @selections.push(selection)
    else
      @removeSelection(@getHead())
    @updateProperties()

  clearSelections: ({except}={}) ->
    for selection in @selections.slice() when (selection isnt except)
      @removeSelection(selection)

  removeEmptySelections: ->
    for selection in @selections.slice() when selection.isEmpty()
      @removeSelection(selection)

  removeSelection: (selection) ->
    _.remove(@selections, selection)
    selection.destroy()

  setHeadBufferRange: (range, options) ->
    head = @getHead()
    @clearSelections(except: head)
    {goalColumn} = head.cursor
    # When reversed state of selection change, goalColumn is cleared.
    # But here for blockwise, I want to keep goalColumn unchanged.
    # This behavior is not identical to pure Vim I know.
    # But I believe this is more unnoisy and less confusion while moving
    # cursor in visual-block mode.
    head.setBufferRange(range, options)
    head.cursor.goalColumn ?= goalColumn if goalColumn?

  restoreCharacterwise: ->
    @setHeadBufferRange(@getBufferRange(), reversed: @isReversed())

  getSelections: ->
    @selections

module.exports = BlockwiseSelection
