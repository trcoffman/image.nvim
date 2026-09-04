local notify = vim.notify
vim.notify = function() end

local renderer = require("image/renderer")
local utils = require("image/utils")

vim.notify = notify

describe("renderer conceal positioning", function()
  local buffer
  local calls
  local namespace
  local original_window
  local originals
  local state
  local window

  local configure_window = function(opts)
    vim.api.nvim_buf_clear_namespace(buffer, namespace, 0, -1)
    vim.api.nvim_buf_set_lines(buffer, 0, -1, false, { opts.line, "parking" })
    vim.api.nvim_win_set_width(window, opts.width or 30)
    vim.wo[window].breakindent = opts.breakindent == true
    vim.wo[window].concealcursor = "nivc"
    vim.wo[window].conceallevel = opts.conceallevel or 2
    vim.wo[window].foldcolumn = opts.foldcolumn or "0"
    vim.wo[window].linebreak = opts.linebreak == true
    vim.wo[window].number = opts.number == true
    vim.wo[window].relativenumber = false
    vim.wo[window].rightleft = opts.rightleft == true
    vim.wo[window].showbreak = opts.showbreak or ""
    vim.wo[window].signcolumn = opts.signcolumn or "no"
    vim.wo[window].statuscolumn = ""
    vim.wo[window].wrap = opts.wrap == true
    vim.api.nvim_win_set_cursor(window, { 2, 0 })

    for _, mark in ipairs(opts.marks or {}) do
      local extmark_options = {
        end_row = mark.end_row or 0,
        end_col = mark.end_col,
        conceal = mark.conceal or "",
      }
      if mark.hl_group then extmark_options.hl_group = mark.hl_group end
      if mark.priority then extmark_options.priority = mark.priority end
      if mark.virt_text then
        extmark_options.virt_text = mark.virt_text
        extmark_options.virt_text_pos = "inline"
      end
      vim.api.nvim_buf_set_extmark(buffer, namespace, mark.row or 0, mark.col, extmark_options)
    end

    calls = {}
    state.images = {}
    vim.api.nvim_set_current_win(window)
    vim.cmd("redraw!")
  end

  local render_position = function(anchor, opts)
    opts = opts or {}
    local image = {
      id = opts.id or "conceal-position",
      path = "test.png",
      source_format = "png",
      image_width = 1,
      image_height = 1,
      window = window,
      buffer = buffer,
      global_state = state,
      geometry = {
        x = anchor,
        y = 0,
        width = 1,
        height = 1,
      },
      is_rendered = false,
    }
    if opts.without_buffer then image.buffer = nil end
    state.images[image.id] = image

    assert.is_true(renderer.render(image))
    return calls[#calls]
  end

  local visible_position = function(character)
    local info = vim.fn.getwininfo(window)[1]
    for row = info.winrow, info.winrow + info.height - 1 do
      for col = info.wincol, info.wincol + info.width - 1 do
        if vim.fn.screenstring(row, col) == character then return { x = col - 1, y = row } end
      end
    end
  end

  local assert_screenpos_position = function(anchor, opts)
    local screen_pos = vim.fn.screenpos(window, 1, anchor + 1)
    local position = render_position(anchor, opts)
    assert.are.same(screen_pos.col - 1, position.x)
    assert.are.same(screen_pos.row, position.y)
  end

  before_each(function()
    original_window = vim.api.nvim_get_current_win()
    buffer = vim.api.nvim_create_buf(false, true)
    vim.cmd("vsplit")
    window = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_buf(window, buffer)
    namespace = vim.api.nvim_create_namespace("image.nvim-conceal-position-test")

    originals = {
      get_size = utils.term.get_size,
      get_window = utils.window.get_window,
      get_global_offsets = utils.offsets.get_global_offsets,
    }

    utils.term.get_size = function()
      return {
        cell_width = 1,
        cell_height = 1,
        screen_cols = vim.o.columns,
        screen_rows = vim.o.lines,
      }
    end
    utils.window.get_window = function(id)
      local position = vim.api.nvim_win_get_position(id)
      local width = vim.api.nvim_win_get_width(id)
      local height = vim.api.nvim_win_get_height(id)
      return {
        id = id,
        buffer = vim.api.nvim_win_get_buf(id),
        is_visible = true,
        is_floating = false,
        rect = {
          top = position[1],
          right = position[2] + width,
          bottom = position[1] + height,
          left = position[2],
        },
      }
    end
    utils.offsets.get_global_offsets = function()
      return { x = 0, y = 0 }
    end

    calls = {}
    state = {
      options = {
        scale_factor = 1,
        window_overlap_clear_enabled = false,
      },
      images = {},
      backend = {
        features = { crop = true },
        render = function(_, x, y)
          calls[#calls + 1] = { x = x, y = y }
        end,
      },
    }
  end)

  after_each(function()
    utils.term.get_size = originals.get_size
    utils.window.get_window = originals.get_window
    utils.offsets.get_global_offsets = originals.get_global_offsets

    if vim.api.nvim_win_is_valid(original_window) then vim.api.nvim_set_current_win(original_window) end
    if vim.api.nvim_win_is_valid(window) then vim.api.nvim_win_close(window, true) end
    if vim.api.nvim_buf_is_valid(buffer) then vim.api.nvim_buf_delete(buffer, { force = true }) end
  end)

  it("positions multiple Neorg-style inline images after concealed formulas", function()
    configure_window({
      line = "$é$+$bbb$Z",
      marks = {
        { col = 0, end_col = 4, virt_text = { { "   " } } },
        { col = 5, end_col = 10, virt_text = { { "    " } } },
      },
    })

    local plus = assert(visible_position("+"))
    local first = render_position(0, { id = "first-formula" })
    local second = render_position(5, { id = "second-formula" })
    local trailing = render_position(10, { id = "after-formulas" })

    assert.are.same({ x = plus.x - 3, y = plus.y }, first)
    assert.are.same({ x = plus.x + 1, y = plus.y }, second)
    assert.are.same(assert(visible_position("Z")), trailing)
  end)

  it("ignores non-Conceal matches and Conceal matches outside the source segment", function()
    configure_window({
      line = "aXz",
      conceallevel = 3,
      marks = { { col = 0, end_col = 1 } },
    })
    vim.api.nvim_win_call(window, function()
      vim.fn.matchadd("Conceal", "\\%#=1z")
      vim.fn.matchaddpos("Conceal", { { 1, 3, 1 }, { 2 } })
      vim.fn.matchadd("Normal", "a", 10, -1, { conceal = "*" })
    end)
    vim.cmd("redraw!")

    assert.are.same(assert(visible_position("X")), render_position(1))
  end)

  it("uses screenpos when pattern match conceal intersects the source segment", function()
    configure_window({
      line = "abX",
      conceallevel = 3,
      marks = { { col = 0, end_col = 1 } },
    })
    vim.api.nvim_win_call(window, function()
      vim.fn.matchadd("Conceal", "b")
    end)
    vim.cmd("redraw!")

    assert_screenpos_position(2)
  end)

  it("uses screenpos when positional match conceal intersects the source segment", function()
    configure_window({
      line = "abX",
      conceallevel = 3,
      marks = { { col = 0, end_col = 1 } },
    })
    vim.api.nvim_win_call(window, function()
      vim.fn.matchaddpos("Conceal", { { 1, 2, 0 } })
    end)
    vim.cmd("redraw!")

    assert_screenpos_position(2)
  end)

  it("uses screenpos when multiline match conceal intersects the source segment", function()
    configure_window({
      line = "abX",
      conceallevel = 3,
      marks = { { col = 0, end_col = 1 } },
    })
    vim.api.nvim_win_call(window, function()
      vim.fn.matchadd("Conceal", "b\\_sparking")
    end)
    vim.cmd("redraw!")

    assert_screenpos_position(2)
  end)

  it("uses Neovim's wrapped row with linebreak, breakindent, and showbreak", function()
    configure_window({
      line = "    " .. string.rep("a", 11) .. " bbbbX",
      width = 20,
      wrap = true,
      linebreak = true,
      breakindent = true,
      showbreak = ">>",
      marks = { { col = 16, end_col = 20 } },
    })

    assert.are.same(assert(visible_position("X")), render_position(20))
  end)

  it("uses screenpos when wide conceal begins on a wrapped row", function()
    configure_window({
      line = "qqqqqqq 界 界界X",
      width = 12,
      wrap = true,
      showbreak = ">>",
      marks = { { col = 12, end_col = 18 } },
    })

    assert_screenpos_position(18)
  end)

  it("positions a reconstructable wrapped right-to-left anchor", function()
    configure_window({
      line = "a bbbb cX",
      width = 6,
      wrap = true,
      rightleft = true,
      showbreak = ">>",
      marks = { { col = 7, end_col = 8 } },
    })

    assert.are.same(assert(visible_position("X")), render_position(8))
  end)

  it("positions a right-to-left anchor after window gutters", function()
    vim.cmd("wincmd L")
    configure_window({
      line = "a bbbb cX",
      width = 20,
      rightleft = true,
      foldcolumn = "1",
      number = true,
      signcolumn = "yes",
      marks = { { col = 7, end_col = 8 } },
    })

    assert.are.same(assert(visible_position("X")), render_position(8))
  end)

  it("positions an image after concealed source preceded by a visible tab", function()
    configure_window({
      line = "\tabcX",
      marks = { { col = 1, end_col = 4 } },
    })

    assert.are.same(assert(visible_position("X")), render_position(4))
  end)

  it("positions an image after a tab that follows concealed source", function()
    configure_window({
      line = "abc\tX",
      marks = { { col = 0, end_col = 3 } },
    })

    assert.are.same(assert(visible_position("X")), render_position(4))
  end)

  it("positions an image in a horizontally scrolled window", function()
    configure_window({
      line = "bX",
      width = 8,
      foldcolumn = "1",
      number = true,
      signcolumn = "yes",
      marks = { { col = 0, end_col = 1 } },
    })
    vim.api.nvim_win_set_cursor(window, { 1, 1 })
    vim.cmd("redraw!")

    assert.are.same(assert(visible_position("X")), render_position(1))
  end)

  it("positions an image after replacement conceal at conceallevel 3", function()
    configure_window({
      line = "abcX",
      conceallevel = 3,
      marks = { { col = 0, end_col = 3, conceal = "*" } },
    })

    assert.are.same(assert(visible_position("X")), render_position(3))
  end)

  it("uses screenpos when conceal replacement priority cannot be reconstructed", function()
    configure_window({
      line = "abcX",
      marks = {
        { col = 0, end_col = 3, conceal = "*", priority = 50 },
        { col = 1, end_col = 2, conceal = "#", priority = 100, hl_group = "Normal" },
      },
    })

    assert_screenpos_position(3)
  end)

  it("does not count overlapping concealed ranges twice", function()
    configure_window({
      line = "abX",
      marks = {
        { col = 0, end_col = 2 },
        { col = 1, end_col = 2 },
      },
    })

    assert.are.same(assert(visible_position("X")), render_position(2))
  end)

  it("uses screenpos for invalid UTF-8 extmark boundaries", function()
    configure_window({
      line = "éaX",
      marks = { { col = 1, end_col = 3 } },
    })
    assert_screenpos_position(3)

    configure_window({
      line = "éaX",
      marks = { { col = 0, end_col = 1 } },
    })
    assert_screenpos_position(3)
  end)

  it("uses screenpos for images without a buffer", function()
    configure_window({
      line = "abcX",
      marks = { { col = 0, end_col = 3 } },
    })

    assert_screenpos_position(3, { without_buffer = true })
  end)
end)
