-- Tests for sigil.motions module
describe("sigil.motions", function()
	local motions
	local config
	local state
	local prettify
	local buf

	-- Test symbols (not dependent on default config)
	local test_symbols = {
		["lambda"] = "λ",
		["->"] = "→",
	}

	before_each(function()
		-- Clear module cache
		package.loaded["sigil.motions"] = nil
		package.loaded["sigil.config"] = nil
		package.loaded["sigil.state"] = nil
		package.loaded["sigil.extmark"] = nil
		package.loaded["sigil.prettify"] = nil

		motions = require("sigil.motions")
		config = require("sigil.config")
		state = require("sigil.state")
		prettify = require("sigil.prettify")

		config.setup({ symbols = test_symbols })

		-- Use current buffer
		buf = vim.api.nvim_get_current_buf()
	end)

	after_each(function()
		-- Cleanup buffer state
		if state.is_attached(buf) then
			state.detach(buf)
		end
	end)

	describe("get_symbol_at", function()
		before_each(function()
			vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "x -> y" })
			state.attach(buf)
			prettify.prettify_buffer(buf)
		end)

		it("should return nil when not on a symbol", function()
			-- Position 0 is 'x', not on a symbol
			local symbol = motions.get_symbol_at(buf, 0, 0)
			assert.is_nil(symbol)
		end)

		it("should return symbol info when on a symbol", function()
			-- Position 2 is start of '->'
			local symbol = motions.get_symbol_at(buf, 0, 2)

			assert.is_not_nil(symbol)
			assert.equals(2, symbol.start_col)
			assert.equals(4, symbol.end_col)
			assert.equals("→", symbol.replacement)
		end)

		it("should return symbol info when inside a symbol", function()
			-- Position 3 is inside '->'
			local symbol = motions.get_symbol_at(buf, 0, 3)

			assert.is_not_nil(symbol)
			assert.equals(2, symbol.start_col)
			assert.equals(4, symbol.end_col)
		end)

		it("should return nil when sigil is disabled", function()
			state.disable(buf)
			local symbol = motions.get_symbol_at(buf, 0, 2)
			assert.is_nil(symbol)
		end)
	end)

	describe("get_next_symbol", function()
		before_each(function()
			vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "x -> y -> z" })
			state.attach(buf)
			prettify.prettify_buffer(buf)
		end)

		it("should find next symbol after position", function()
			-- After 'x', next symbol is '->' at col 2
			local symbol = motions.get_next_symbol(buf, 0, 0)

			assert.is_not_nil(symbol)
			assert.equals(2, symbol.start_col)
		end)

		it("should find second symbol when past first", function()
			-- After first '->' (col 4), next symbol is second '->' at col 7
			local symbol = motions.get_next_symbol(buf, 0, 4)

			assert.is_not_nil(symbol)
			assert.equals(7, symbol.start_col)
		end)

		it("should return nil when no more symbols", function()
			-- After second '->' at col 9, no more symbols
			local symbol = motions.get_next_symbol(buf, 0, 9)
			assert.is_nil(symbol)
		end)
	end)

	describe("get_prev_symbol", function()
		before_each(function()
			vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "x -> y -> z" })
			state.attach(buf)
			prettify.prettify_buffer(buf)
		end)

		it("should find previous symbol before position", function()
			-- Before 'z' (col 10), prev symbol is second '->' ending at col 9
			local symbol = motions.get_prev_symbol(buf, 0, 10)

			assert.is_not_nil(symbol)
			assert.equals(7, symbol.start_col)
		end)

		it("should return nil when no previous symbols", function()
			-- At col 0, no previous symbols
			local symbol = motions.get_prev_symbol(buf, 0, 0)
			assert.is_nil(symbol)
		end)
	end)

	describe("move_right", function()
		before_each(function()
			vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "x -> y" })
			state.attach(buf)
			prettify.prettify_buffer(buf)
		end)

		it("should skip over symbol when cursor is on it", function()
			-- Start on '->' at col 2
			vim.api.nvim_win_set_cursor(0, { 1, 2 })
			motions.move_right()

			local cursor = vim.api.nvim_win_get_cursor(0)
			-- Should be at col 4 (after '->'), which is space before 'y'
			assert.equals(4, cursor[2])
		end)

		it("should skip over symbol when cursor is inside it", function()
			-- Start inside '->' at col 3 (on '>')
			vim.api.nvim_win_set_cursor(0, { 1, 3 })
			motions.move_right()

			local cursor = vim.api.nvim_win_get_cursor(0)
			-- Should be at col 4 (after '->')
			assert.equals(4, cursor[2])
		end)

		it("should move normally when not on symbol", function()
			-- Start at col 0 ('x')
			vim.api.nvim_win_set_cursor(0, { 1, 0 })
			motions.move_right()

			local cursor = vim.api.nvim_win_get_cursor(0)
			-- Should be at col 1 (space)
			assert.equals(1, cursor[2])
		end)

		it("should move normally to symbol start when before symbol", function()
			-- Start at col 1 (space before '->')
			vim.api.nvim_win_set_cursor(0, { 1, 1 })
			motions.move_right()

			local cursor = vim.api.nvim_win_get_cursor(0)
			-- Should be at col 2 (start of '->'), NOT col 4
			assert.equals(2, cursor[2])
		end)
	end)

	describe("move_left", function()
		before_each(function()
			vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "x -> y" })
			state.attach(buf)
			prettify.prettify_buffer(buf)
		end)

		it("should skip to start of symbol when inside it", function()
			-- Start inside '->' at col 3
			vim.api.nvim_win_set_cursor(0, { 1, 3 })
			motions.move_left()

			local cursor = vim.api.nvim_win_get_cursor(0)
			-- Should be at col 2 (start of '->')
			assert.equals(2, cursor[2])
		end)

		it("should skip over symbol when immediately after it", function()
			-- Start at col 4 (space after '->')
			vim.api.nvim_win_set_cursor(0, { 1, 4 })
			motions.move_left()

			local cursor = vim.api.nvim_win_get_cursor(0)
			-- Should be at col 2 (start of '->')
			assert.equals(2, cursor[2])
		end)

		it("should move normally when not near symbol", function()
			-- Start at col 5 ('y')
			vim.api.nvim_win_set_cursor(0, { 1, 5 })
			motions.move_left()

			local cursor = vim.api.nvim_win_get_cursor(0)
			-- Should be at col 4 (space before 'y')
			assert.equals(4, cursor[2])
		end)
	end)

	describe("move_word_forward", function()
		before_each(function()
			vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "foo -> bar baz" })
			state.attach(buf)
			prettify.prettify_buffer(buf)
		end)

		it("should move to next word start", function()
			-- Start at col 0 ('f')
			vim.api.nvim_win_set_cursor(0, { 1, 0 })
			motions.move_word_forward()

			local cursor = vim.api.nvim_win_get_cursor(0)
			-- Should be at col 4 (start of '->')
			assert.equals(4, cursor[2])
		end)

		it("should skip over symbol to next word", function()
			-- Start on '->' at col 4
			vim.api.nvim_win_set_cursor(0, { 1, 4 })
			motions.move_word_forward()

			local cursor = vim.api.nvim_win_get_cursor(0)
			-- Should be at col 7 ('b' of 'bar')
			assert.equals(7, cursor[2])
		end)

		it("should move normally between regular words", function()
			-- Start at col 7 ('b' of 'bar')
			vim.api.nvim_win_set_cursor(0, { 1, 7 })
			motions.move_word_forward()

			local cursor = vim.api.nvim_win_get_cursor(0)
			-- Should be at col 11 ('b' of 'baz')
			assert.equals(11, cursor[2])
		end)
	end)

	describe("move_word_backward", function()
		before_each(function()
			vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "foo -> bar baz" })
			state.attach(buf)
			prettify.prettify_buffer(buf)
		end)

		it("should move to previous word start", function()
			-- Start at col 11 ('b' of 'baz')
			vim.api.nvim_win_set_cursor(0, { 1, 11 })
			motions.move_word_backward()

			local cursor = vim.api.nvim_win_get_cursor(0)
			-- Should be at col 7 ('b' of 'bar')
			assert.equals(7, cursor[2])
		end)

		it("should skip over symbol when moving backward", function()
			-- Start at col 7 ('b' of 'bar')
			vim.api.nvim_win_set_cursor(0, { 1, 7 })
			motions.move_word_backward()

			local cursor = vim.api.nvim_win_get_cursor(0)
			-- Should be at col 4 (start of '->')
			assert.equals(4, cursor[2])
		end)

		it("should move to word start before symbol", function()
			-- Start at col 4 (start of '->')
			vim.api.nvim_win_set_cursor(0, { 1, 4 })
			motions.move_word_backward()

			local cursor = vim.api.nvim_win_get_cursor(0)
			-- Should be at col 0 ('f' of 'foo')
			assert.equals(0, cursor[2])
		end)
	end)

	describe("move_word_end", function()
		before_each(function()
			vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "foo -> bar baz" })
			state.attach(buf)
			prettify.prettify_buffer(buf)
		end)

		it("should move to end of next word", function()
			-- Start at col 0 ('f')
			vim.api.nvim_win_set_cursor(0, { 1, 0 })
			motions.move_word_end()

			local cursor = vim.api.nvim_win_get_cursor(0)
			-- Should be at col 2 ('o' of 'foo')
			assert.equals(2, cursor[2])
		end)

		it("should move to end of symbol", function()
			-- Start at col 3 (space before '->')
			vim.api.nvim_win_set_cursor(0, { 1, 3 })
			motions.move_word_end()

			local cursor = vim.api.nvim_win_get_cursor(0)
			-- Should be at col 4 (start of '->'), visually "on" the concealed symbol
			assert.equals(4, cursor[2])
		end)

		it("should skip over symbol to next word end", function()
			-- Start at col 5 ('>' of '->')
			vim.api.nvim_win_set_cursor(0, { 1, 5 })
			motions.move_word_end()

			local cursor = vim.api.nvim_win_get_cursor(0)
			-- Should be at col 9 ('r' of 'bar')
			assert.equals(9, cursor[2])
		end)
	end)

	describe("delete_char", function()
		before_each(function()
			vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "x -> y" })
			state.attach(buf)
			prettify.prettify_buffer(buf)
		end)

		it("should delete entire symbol when cursor is on it", function()
			-- Start on '->' at col 2
			vim.api.nvim_win_set_cursor(0, { 1, 2 })
			motions.delete_char()

			local line = vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1]
			-- '->' should be deleted, leaving "x  y"
			assert.equals("x  y", line)
		end)

		it("should delete entire symbol when cursor is inside it", function()
			-- Start inside '->' at col 3 (on '>')
			vim.api.nvim_win_set_cursor(0, { 1, 3 })
			motions.delete_char()

			local line = vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1]
			assert.equals("x  y", line)
		end)

		it("should delete single char when not on symbol", function()
			-- Start at col 0 ('x')
			vim.api.nvim_win_set_cursor(0, { 1, 0 })
			motions.delete_char()

			local line = vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1]
			-- 'x' should be deleted
			assert.equals(" -> y", line)
		end)

		it("should keep other symbols prettified on the same line", function()
			vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "x -> y -> z" })
			prettify.prettify_buffer(buf)

			-- Delete first symbol
			vim.api.nvim_win_set_cursor(0, { 1, 2 })
			motions.delete_char()

			local line = vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1]
			local start = line:find("->", 1, true)
			assert.is_not_nil(start)

			local symbol = motions.get_symbol_at(buf, 0, start - 1)
			assert.is_not_nil(symbol)
		end)
	end)

	describe("delete_char_before", function()
		before_each(function()
			vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "x -> y" })
			state.attach(buf)
			prettify.prettify_buffer(buf)
		end)

		it("should delete entire symbol when immediately after it", function()
			-- Start at col 4 (space after '->')
			vim.api.nvim_win_set_cursor(0, { 1, 4 })
			motions.delete_char_before()

			local line = vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1]
			-- '->' should be deleted
			assert.equals("x  y", line)
		end)

		it("should delete single char when not after symbol", function()
			-- Start at col 5 ('y')
			vim.api.nvim_win_set_cursor(0, { 1, 5 })
			motions.delete_char_before()

			local line = vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1]
			-- space before 'y' should be deleted
			assert.equals("x ->y", line)
		end)
	end)

	describe("insert_backspace", function()
		before_each(function()
			vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "x -> y" })
			state.attach(buf)
			prettify.prettify_buffer(buf)
		end)

		-- Helper to convert key notation to terminal codes for comparison
		local function termcodes(str)
			return vim.api.nvim_replace_termcodes(str, true, false, true)
		end

		it("should return repeated <BS> when immediately after symbol", function()
			-- Start at col 4 (space after '->')
			vim.api.nvim_win_set_cursor(0, { 1, 4 })
			local res = motions.insert_backspace()

			assert.equals(termcodes("<BS><BS>"), res)
		end)

		it("should return <BS><Del> when cursor is inside symbol", function()
			-- Start inside '->' at col 3 (on '>')
			vim.api.nvim_win_set_cursor(0, { 1, 3 })
			local res = motions.insert_backspace()

			assert.equals(termcodes("<BS><Del>"), res)
		end)

		it("should return <BS> when not after symbol", function()
			-- Start at col 5 ('y')
			vim.api.nvim_win_set_cursor(0, { 1, 5 })
			local res = motions.insert_backspace()

			local line = vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1]
			assert.equals("x -> y", line)
			assert.equals(termcodes("<BS>"), res)
		end)

		it("should translate keycodes returned by the original expr mapping", function()
			pcall(vim.keymap.del, "i", "<BS>")
			vim.keymap.set("i", "<BS>", function()
				return "<BS>"
			end, { expr = true })

			motions.setup_keymaps(buf)
			vim.api.nvim_win_set_cursor(0, { 1, 5 })
			local res = motions.insert_backspace()

			motions.remove_keymaps(buf)
			pcall(vim.keymap.del, "i", "<BS>")

			assert.equals(termcodes("<BS>"), res)
			assert.not_equals("<BS>", res)
		end)
	end)

	describe("substitute_char", function()
		before_each(function()
			vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "x -> y" })
			state.attach(buf)
			prettify.prettify_buffer(buf)
		end)

		it("should delete entire symbol when cursor is on it", function()
			-- Start on '->' at col 2
			vim.api.nvim_win_set_cursor(0, { 1, 2 })
			motions.substitute_char()

			local line = vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1]
			-- '->' should be deleted, leaving "x  y"
			assert.equals("x  y", line)

			-- Cursor should be at position where symbol was
			local cursor = vim.api.nvim_win_get_cursor(0)
			assert.equals(2, cursor[2])

			-- Note: startinsert may not work in headless mode, so we don't check mode
			-- Exit insert mode for cleanup (in case it worked)
			vim.cmd("stopinsert")
		end)

		it("should delete entire symbol when cursor is inside it", function()
			-- Start inside '->' at col 3 (on '>')
			vim.api.nvim_win_set_cursor(0, { 1, 3 })
			motions.substitute_char()

			local line = vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1]
			assert.equals("x  y", line)

			-- Exit insert mode for cleanup
			vim.cmd("stopinsert")
		end)

		it("should delete single char when not on symbol", function()
			-- Start at col 5 ('y') - not on a prettified symbol
			vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "x -> y" })
			vim.api.nvim_win_set_cursor(0, { 1, 5 })

			-- For non-symbol, it calls normal! s which deletes 'y'
			motions.substitute_char()

			local line = vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1]
			-- 'y' should be deleted by normal! s
			assert.equals("x -> ", line)

			-- Exit insert mode for cleanup
			vim.cmd("stopinsert")
		end)
	end)

	describe("change_opfunc", function()
		before_each(function()
			vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "foo -> bar" })
			state.attach(buf)
			prettify.prettify_buffer(buf)
		end)

		it("should expand range to include whole symbol at start", function()
			-- Set marks to simulate a motion that starts inside a symbol
			-- '->' is at col 4-5, 'bar' starts at col 7
			vim.api.nvim_buf_set_mark(buf, "[", 1, 4, {}) -- start of '->'
			vim.api.nvim_buf_set_mark(buf, "]", 1, 6, {}) -- space after

			motions.change_opfunc("char")

			local line = vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1]
			-- Should delete from start of '->' to end of range
			assert.equals("foo bar", line)

			vim.cmd("stopinsert")
		end)

		it("should expand range to include whole symbol at end", function()
			-- Set marks: start before symbol, end inside symbol
			vim.api.nvim_buf_set_mark(buf, "[", 1, 3, {}) -- space before '->'
			vim.api.nvim_buf_set_mark(buf, "]", 1, 5, {}) -- '>' of '->'

			motions.change_opfunc("char")

			local line = vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1]
			-- Should delete space and entire '->'
			assert.equals("foo bar", line)

			vim.cmd("stopinsert")
		end)
	end)

	describe("append_after", function()
		before_each(function()
			vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "x -> y" })
			state.attach(buf)
			prettify.prettify_buffer(buf)
		end)

		it("should move cursor to end of symbol and enter insert mode", function()
			-- Start on '->' at col 2
			vim.api.nvim_win_set_cursor(0, { 1, 2 })
			motions.append_after()

			local cursor = vim.api.nvim_win_get_cursor(0)
			-- Should be at col 4 (after '->')
			assert.equals(4, cursor[2])

			vim.cmd("stopinsert")
		end)

		it("should behave like normal 'a' when not on symbol", function()
			-- Start at col 0 ('x')
			vim.api.nvim_win_set_cursor(0, { 1, 0 })
			motions.append_after()

			local cursor = vim.api.nvim_win_get_cursor(0)
			-- Should be at col 1 (after 'x')
			assert.equals(1, cursor[2])

			vim.cmd("stopinsert")
		end)

		it("should handle cursor inside symbol", function()
			-- Start inside '->' at col 3 (on '>')
			vim.api.nvim_win_set_cursor(0, { 1, 3 })
			motions.append_after()

			local cursor = vim.api.nvim_win_get_cursor(0)
			-- Should be at col 4 (after '->')
			assert.equals(4, cursor[2])

			vim.cmd("stopinsert")
		end)
	end)

	describe("insert_move_right", function()
		-- Helper to convert key notation to terminal codes
		local function termcodes(str)
			return vim.api.nvim_replace_termcodes(str, true, false, true)
		end

		before_each(function()
			vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "x -> y" })
			state.attach(buf)
			prettify.prettify_buffer(buf)
		end)

		it("should skip over symbol when cursor is on it", function()
			-- Start on '->' at col 2
			vim.api.nvim_win_set_cursor(0, { 1, 2 })
			local res = motions.insert_move_right()

			-- '->' is 2 chars, should return 2 <Right> presses
			assert.equals(string.rep(termcodes("<Right>"), 2), res)
		end)

		it("should return default when not on symbol", function()
			-- Start at col 0 ('x')
			vim.api.nvim_win_set_cursor(0, { 1, 0 })
			local res = motions.insert_move_right()

			-- Should return default <C-f> terminal code
			assert.equals(termcodes("<C-f>"), res)
		end)

		it("should return default when at end of line", function()
			vim.api.nvim_win_set_cursor(0, { 1, 5 })
			local res = motions.insert_move_right()

			-- At last char 'y', col 5, line length is 6 so col < #line
			-- Since 'y' is not a symbol, should return <C-f>
			assert.equals(termcodes("<C-f>"), res)
		end)
	end)

	describe("insert_move_left", function()
		-- Helper to convert key notation to terminal codes
		local function termcodes(str)
			return vim.api.nvim_replace_termcodes(str, true, false, true)
		end

		before_each(function()
			vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "x -> y" })
			state.attach(buf)
			prettify.prettify_buffer(buf)
		end)

		it("should skip over symbol when cursor is immediately after it", function()
			-- Start at col 4 (space after '->')
			vim.api.nvim_win_set_cursor(0, { 1, 4 })
			local res = motions.insert_move_left()

			-- '->' is 2 chars starting at col 2; cursor at col 4
			-- col - start_col = 4 - 2 = 2 chars to skip
			assert.equals(string.rep(termcodes("<Left>"), 2), res)
		end)

		it("should return default when not after symbol", function()
			-- Start at col 5 ('y')
			vim.api.nvim_win_set_cursor(0, { 1, 5 })
			local res = motions.insert_move_left()

			-- Position before is space (col 4), not a symbol
			assert.equals(termcodes("<C-b>"), res)
		end)

		it("should return default at start of line", function()
			vim.api.nvim_win_set_cursor(0, { 1, 0 })
			local res = motions.insert_move_left()

			assert.equals(termcodes("<C-b>"), res)
		end)
	end)

	describe("multi-char symbols", function()
		before_each(function()
			vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "lambda x" })
			state.attach(buf)
			prettify.prettify_buffer(buf)
		end)

		it("should skip over 'lambda' with move_right", function()
			-- Start on 'lambda' at col 0
			vim.api.nvim_win_set_cursor(0, { 1, 0 })
			motions.move_right()

			local cursor = vim.api.nvim_win_get_cursor(0)
			-- 'lambda' is 6 chars, should jump to col 6 (space before 'x')
			assert.equals(6, cursor[2])
		end)

		it("should skip to start of 'lambda' with move_left", function()
			-- Start at col 6 (space after 'lambda')
			vim.api.nvim_win_set_cursor(0, { 1, 6 })
			motions.move_left()

			local cursor = vim.api.nvim_win_get_cursor(0)
			-- Should land at col 0 (start of 'lambda')
			assert.equals(0, cursor[2])
		end)

		it("should snap to start when inside 'lambda' with move_left", function()
			-- Start inside 'lambda' at col 3 ('b')
			vim.api.nvim_win_set_cursor(0, { 1, 3 })
			motions.move_left()

			local cursor = vim.api.nvim_win_get_cursor(0)
			assert.equals(0, cursor[2])
		end)

		it("should delete entire 'lambda' with delete_char", function()
			-- Start on 'lambda' at col 0
			vim.api.nvim_win_set_cursor(0, { 1, 0 })
			motions.delete_char()

			local line = vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1]
			assert.equals(" x", line)
		end)

		it("should substitute entire 'lambda' with substitute_char", function()
			vim.api.nvim_win_set_cursor(0, { 1, 0 })
			motions.substitute_char()

			local line = vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1]
			assert.equals(" x", line)

			vim.cmd("stopinsert")
		end)
	end)

	describe("multiple symbols on line", function()
		before_each(function()
			vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "x -> y -> z" })
			state.attach(buf)
			prettify.prettify_buffer(buf)
		end)

		it("should navigate through multiple symbols with move_right", function()
			-- Start at col 0 ('x')
			vim.api.nvim_win_set_cursor(0, { 1, 0 })
			motions.move_right() -- col 1 (space)
			motions.move_right() -- col 2 (start of first '->')
			motions.move_right() -- col 4 (past first '->')

			local cursor = vim.api.nvim_win_get_cursor(0)
			assert.equals(4, cursor[2])

			motions.move_right() -- col 5 (' ')
			motions.move_right() -- col 6 ('y')
			motions.move_right() -- col 7 (start of second '->')
			motions.move_right() -- col 9 (past second '->')

			cursor = vim.api.nvim_win_get_cursor(0)
			assert.equals(9, cursor[2])
		end)

		it("should delete first symbol and keep second", function()
			vim.api.nvim_win_set_cursor(0, { 1, 2 })
			motions.delete_char()

			local line = vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1]
			assert.equals("x  y -> z", line)

			-- Second symbol should still be prettified
			local second_arrow_col = line:find("->", 1, true)
			assert.is_not_nil(second_arrow_col)
		end)
	end)

	describe("keymaps", function()
		it("should setup keymaps for buffer", function()
			motions.setup_keymaps(buf)

			-- Check that keymaps exist
			local keymaps = vim.api.nvim_buf_get_keymap(buf, "n")
			local expected = { "l", "h", "w", "b", "e", "x", "X", "s", "c" }
			local found = {}

			for _, map in ipairs(keymaps) do
				for _, key in ipairs(expected) do
					if map.lhs == key then
						found[key] = true
					end
				end
			end

			for _, key in ipairs(expected) do
				assert.is_true(found[key], key .. " keymap should be set")
			end

			local imaps = vim.api.nvim_buf_get_keymap(buf, "i")
			local has_bs = false
			for _, map in ipairs(imaps) do
				if map.lhs == "<BS>" then
					has_bs = true
					break
				end
			end
			assert.is_true(has_bs, "<BS> keymap should be set")

			-- Cleanup
			motions.remove_keymaps(buf)
		end)

		it("should remove keymaps from buffer", function()
			motions.setup_keymaps(buf)
			motions.remove_keymaps(buf)

			local keymaps = vim.api.nvim_buf_get_keymap(buf, "n")
			local expected = { "l", "h", "w", "b", "e", "x", "X", "s", "c" }
			local found = {}

			for _, map in ipairs(keymaps) do
				for _, key in ipairs(expected) do
					if map.lhs == key then
						found[key] = true
					end
				end
			end

			for _, key in ipairs(expected) do
				assert.is_falsy(found[key], key .. " keymap should be removed")
			end

			local imaps = vim.api.nvim_buf_get_keymap(buf, "i")
			local has_bs = false
			for _, map in ipairs(imaps) do
				if map.lhs == "<BS>" then
					has_bs = true
					break
				end
			end
			assert.is_falsy(has_bs, "<BS> keymap should be removed")
		end)
	end)
end)
