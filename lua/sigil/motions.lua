-- sigil.nvim - Atomic symbol motions
-- Makes prettified symbols behave as single characters for navigation

local state = require("sigil.state")

local M = {}

-- Storage for original mappings (to support fallback to mini-pairs, etc.)
local original_mappings = {}

---Get extmarks for a line, sorted by start column
---@param buf integer
---@param row integer
---@return table[]
local function get_line_marks(buf, row)
	local marks = vim.api.nvim_buf_get_extmarks(buf, state.ns, { row, 0 }, { row, -1 }, { details = true })
	local result = {}
	for _, mark in ipairs(marks) do
		local start_col = mark[3]
		local end_col = mark[4].end_col or (start_col + 1)
		if end_col > start_col then
			table.insert(result, { start_col = start_col, end_col = end_col })
		end
	end
	table.sort(result, function(a, b)
		return a.start_col < b.start_col
	end)
	return result
end

---Get display width for a substring (tabs + multibyte aware)
---@param str string
---@return integer
local function display_width(str)
	if str == "" then
		return 0
	end
	return vim.fn.strdisplaywidth(str)
end

---If column is inside a symbol, snap to its start
---@param col integer
---@param marks table[]
---@return integer
local function snap_col_to_symbol(col, marks)
	for _, mark in ipairs(marks) do
		if col >= mark.start_col and col < mark.end_col then
			return mark.start_col
		end
	end
	return col
end

---Get display column (conceal-aware) for a byte column
---@param line string
---@param col integer
---@param marks table[]
---@return integer
local function display_col_for_byte(line, col, marks)
	if line == "" then
		return 0
	end

	local line_len = #line
	col = math.max(0, math.min(col, line_len))

	local disp = 0
	local byte_idx = 0

	for _, mark in ipairs(marks) do
		if col <= mark.start_col then
			local segment = line:sub(byte_idx + 1, col)
			disp = disp + display_width(segment)
			return disp
		end

		local segment = line:sub(byte_idx + 1, mark.start_col)
		disp = disp + display_width(segment)

		if col < mark.end_col then
			-- Inside concealed region: cursor displays at start
			return disp
		end

		disp = disp + 1
		byte_idx = mark.end_col
	end

	local segment = line:sub(byte_idx + 1, col)
	disp = disp + display_width(segment)
	return disp
end

---Find byte offset in a segment for a display offset
---@param segment string
---@param desired_disp integer
---@return integer
local function byte_offset_for_display(segment, desired_disp)
	if desired_disp <= 0 or segment == "" then
		return 0
	end

	local char_count = vim.fn.strchars(segment)
	local disp = 0
	local byte_off = 0

	for i = 0, char_count - 1 do
		local ch = vim.fn.strcharpart(segment, i, 1)
		local w = display_width(ch)
		if disp + w > desired_disp then
			return byte_off
		end
		disp = disp + w
		byte_off = byte_off + #ch
	end

	return byte_off
end

---Map a display column (conceal-aware) to a byte column
---@param line string
---@param desired_disp integer
---@param marks table[]
---@return integer
local function byte_col_for_display(line, desired_disp, marks)
	if line == "" then
		return 0
	end

	local line_len = #line
	if desired_disp <= 0 then
		return 0
	end

	local byte_idx = 0

	for _, mark in ipairs(marks) do
		local segment = line:sub(byte_idx + 1, mark.start_col)
		local seg_width = display_width(segment)

		if desired_disp <= seg_width then
			local off = byte_offset_for_display(segment, desired_disp)
			return math.max(0, math.min(line_len - 1, byte_idx + off))
		end

		desired_disp = desired_disp - seg_width

		-- Concealed region occupies one cell
		if desired_disp <= 1 then
			return math.max(0, math.min(line_len - 1, mark.start_col))
		end

		desired_disp = desired_disp - 1
		byte_idx = mark.end_col
	end

	local tail = line:sub(byte_idx + 1)
	local off = byte_offset_for_display(tail, desired_disp)
	return math.max(0, math.min(line_len - 1, byte_idx + off))
end

---Get conceal-aware display column for current cursor position
---@param buf integer
---@param row integer
---@param col integer
---@return integer
function M.get_display_col(buf, row, col)
	local line = vim.api.nvim_buf_get_lines(buf, row, row + 1, false)[1] or ""
	local marks = get_line_marks(buf, row)
	local snapped = snap_col_to_symbol(col, marks)
	return display_col_for_byte(line, snapped, marks)
end

---Get byte column for a desired display column on a target line
---@param buf integer
---@param row integer
---@param desired_disp integer
---@return integer
function M.get_byte_col_for_display(buf, row, desired_disp)
	local line = vim.api.nvim_buf_get_lines(buf, row, row + 1, false)[1] or ""
	local marks = get_line_marks(buf, row)
	return byte_col_for_display(line, desired_disp, marks)
end

---Move cursor vertically while preserving byte column (not screen column)
---@param delta integer -1 for up, 1 for down
function M.move_vertical(delta)
	local buf = vim.api.nvim_get_current_buf()
	local cursor = vim.api.nvim_win_get_cursor(0)
	local row = cursor[1] - 1
	local col = cursor[2]

	local desired_disp = vim.w.sigil_curswant_disp
	if desired_disp == nil then
		desired_disp = M.get_display_col(buf, row, col)
		vim.w.sigil_curswant_disp = desired_disp
	end

	local count = vim.v.count1
	vim.w.sigil_vert_active = true
	local mode = vim.fn.mode()
	if mode == "v" or mode == "V" or mode == "\22" then
		local key = delta > 0 and "j" or "k"
		local keys = vim.api.nvim_replace_termcodes(tostring(count) .. key, true, false, true)
		vim.api.nvim_feedkeys(keys, "nx", false)
	else
		if delta > 0 then
			vim.cmd("normal! " .. count .. "j")
		else
			vim.cmd("normal! " .. count .. "k")
		end
	end

	local new_cursor = vim.api.nvim_win_get_cursor(0)
	if new_cursor[1] == cursor[1] and new_cursor[2] == cursor[2] then
		vim.w.sigil_vert_active = false
		return
	end

	local target_row = new_cursor[1] - 1
	local target_col = M.get_byte_col_for_display(buf, target_row, desired_disp)

	if target_col ~= new_cursor[2] then
		vim.w.sigil_vert_active = true
		vim.api.nvim_win_set_cursor(0, { target_row + 1, target_col })
	end
end

---Move cursor down (j) preserving byte column
function M.move_down()
	M.move_vertical(1)
end

---Move cursor up (k) preserving byte column
function M.move_up()
	M.move_vertical(-1)
end

---Extract replacement character from extmark details
---@param details table Extmark details
---@return string|nil Replacement character
local function get_replacement(details)
	-- Check virt_text (overlay mode) first, then conceal (legacy mode)
	if details.virt_text and #details.virt_text > 0 then
		return details.virt_text[1][1]
	elseif details.conceal and details.conceal ~= "" then
		return details.conceal
	end
	return nil
end

---Collect symbols for a line (sorted by column)
---@param buf integer
---@param row integer
---@return table[]
local function get_line_symbols(buf, row)
	local marks = vim.api.nvim_buf_get_extmarks(buf, state.ns, { row, 0 }, { row, -1 }, { details = true })
	local symbols = {}
	for _, mark in ipairs(marks) do
		local start_col = mark[3]
		local end_col = mark[4].end_col or (start_col + 1)
		if end_col > start_col then
			table.insert(symbols, {
				id = mark[1],
				start_col = start_col,
				end_col = end_col,
				replacement = get_replacement(mark[4]),
			})
		end
	end
	return symbols
end

---Find symbol at column in a precomputed list
---@param symbols table[]
---@param col integer
---@return table|nil
local function symbol_at(symbols, col)
	for _, symbol in ipairs(symbols) do
		if col >= symbol.start_col and col < symbol.end_col then
			return symbol
		end
	end
	return nil
end

---Find next symbol starting after column in a precomputed list
---@param symbols table[]
---@param col integer
---@return table|nil
local function next_symbol(symbols, col)
	for _, symbol in ipairs(symbols) do
		if symbol.start_col > col then
			return symbol
		end
	end
	return nil
end

---Find previous symbol ending before or at column in a precomputed list
---@param symbols table[]
---@param col integer
---@return table|nil
local function prev_symbol(symbols, col)
	for i = #symbols, 1, -1 do
		local symbol = symbols[i]
		if symbol.end_col <= col then
			return symbol
		end
	end
	return nil
end

---Get extmark info at cursor position if it's a prettified symbol
---@param buf integer Buffer number
---@param row integer 0-indexed row
---@param col integer 0-indexed column
---@param symbols? table[] Precomputed line symbols
---@return table|nil Extmark info {id, start_col, end_col, replacement} or nil
function M.get_symbol_at(buf, row, col, symbols)
	if not state.is_enabled(buf) then
		return nil
	end

	local line_symbols = symbols or get_line_symbols(buf, row)
	return symbol_at(line_symbols, col)
end

---Get extmark starting at or after given column
---@param buf integer
---@param row integer 0-indexed row
---@param col integer 0-indexed column (exclusive, search starts after this)
---@param symbols? table[] Precomputed line symbols
---@return table|nil Extmark info or nil
function M.get_next_symbol(buf, row, col, symbols)
	if not state.is_enabled(buf) then
		return nil
	end

	local line_symbols = symbols or get_line_symbols(buf, row)
	return next_symbol(line_symbols, col)
end

---Get extmark ending at or before given column
---@param buf integer
---@param row integer 0-indexed row
---@param col integer 0-indexed column (exclusive, search ends before this)
---@param symbols? table[] Precomputed line symbols
---@return table|nil Extmark info or nil
function M.get_prev_symbol(buf, row, col, symbols)
	if not state.is_enabled(buf) then
		return nil
	end

	local line_symbols = symbols or get_line_symbols(buf, row)
	return prev_symbol(line_symbols, col)
end

---Move cursor right, treating prettified symbols as single chars
function M.move_right()
	local buf = vim.api.nvim_get_current_buf()
	local cursor = vim.api.nvim_win_get_cursor(0)
	local row = cursor[1] - 1 -- 0-indexed
	local col = cursor[2] -- 0-indexed

	-- Check if we're on a prettified symbol
	local symbols = get_line_symbols(buf, row)
	local symbol = M.get_symbol_at(buf, row, col, symbols)

	if symbol then
		-- Move to end of symbol (past the entire prettified text)
		local line = vim.api.nvim_buf_get_lines(buf, row, row + 1, false)[1]
		local line_len = #line

		if symbol.end_col < line_len then
			vim.api.nvim_win_set_cursor(0, { row + 1, symbol.end_col })
			return
		end
	end

	-- Normal movement (not on a symbol)
	vim.cmd("normal! l")
end

---Move cursor left, treating prettified symbols as single chars
---@return string Empty string (for expr mapping)
function M.move_left()
	local buf = vim.api.nvim_get_current_buf()
	local cursor = vim.api.nvim_win_get_cursor(0)
	local row = cursor[1] - 1 -- 0-indexed
	local col = cursor[2] -- 0-indexed

	-- Check if we're on a prettified symbol (not at its start)
	local symbols = get_line_symbols(buf, row)
	local symbol = M.get_symbol_at(buf, row, col, symbols)

	if symbol and col > symbol.start_col then
		-- Move to start of symbol
		vim.api.nvim_win_set_cursor(0, { row + 1, symbol.start_col })
	else
		-- Check if position to the left is end of a symbol
		if col > 0 then
			local prev_symbol = M.get_symbol_at(buf, row, col - 1, symbols)

			if prev_symbol then
				-- Move to start of that symbol
				vim.api.nvim_win_set_cursor(0, { row + 1, prev_symbol.start_col })
			else
				-- Normal movement
				vim.cmd("normal! h")
			end
		else
			-- At start of line
			vim.cmd("normal! h")
		end
	end

	return ""
end

---Check if character is a word character (alphanumeric or underscore)
---@param char string
---@return boolean
local function is_word_char(char)
	return char:match("[%w_]") ~= nil
end

---Check if character is whitespace
---@param char string
---@return boolean
local function is_whitespace(char)
	return char:match("%s") ~= nil
end

---Move to next word start, treating prettified symbols as word boundaries
function M.move_word_forward()
	local buf = vim.api.nvim_get_current_buf()
	local cursor = vim.api.nvim_win_get_cursor(0)
	local row = cursor[1] - 1 -- 0-indexed
	local col = cursor[2] -- 0-indexed

	local line = vim.api.nvim_buf_get_lines(buf, row, row + 1, false)[1]
	if not line or #line == 0 then
		vim.cmd("normal! w")
		return
	end

	local symbols = get_line_symbols(buf, row)
	-- If we're on a prettified symbol, skip to end of it first
	local symbol = symbol_at(symbols, col)
	if symbol then
		col = symbol.end_col
	else
		-- Skip current word
		local char = line:sub(col + 1, col + 1)
		if is_word_char(char) then
			-- Skip word characters
			while col < #line do
				local next_symbol = symbol_at(symbols, col)
				if next_symbol then
					col = next_symbol.end_col
					break
				end
				local c = line:sub(col + 1, col + 1)
				if not is_word_char(c) then
					break
				end
				col = col + 1
			end
		elseif not is_whitespace(char) then
			-- Skip punctuation
			while col < #line do
				local next_symbol = symbol_at(symbols, col)
				if next_symbol then
					col = next_symbol.end_col
					break
				end
				local c = line:sub(col + 1, col + 1)
				if is_word_char(c) or is_whitespace(c) then
					break
				end
				col = col + 1
			end
		end
	end

	-- Skip whitespace
	while col < #line do
		local c = line:sub(col + 1, col + 1)
		if not is_whitespace(c) then
			break
		end
		col = col + 1
	end

	-- If at end of line, use normal 'w' to go to next line
	if col >= #line then
		vim.cmd("normal! w")
		return
	end

	vim.api.nvim_win_set_cursor(0, { row + 1, col })
end

---Move to previous word start, treating prettified symbols as word boundaries
function M.move_word_backward()
	local buf = vim.api.nvim_get_current_buf()
	local cursor = vim.api.nvim_win_get_cursor(0)
	local row = cursor[1] - 1 -- 0-indexed
	local col = cursor[2] -- 0-indexed

	local line = vim.api.nvim_buf_get_lines(buf, row, row + 1, false)[1]
	if not line or col == 0 then
		vim.cmd("normal! b")
		return
	end

	local symbols = get_line_symbols(buf, row)
	-- Move one position left first
	col = col - 1

	-- Skip whitespace going backward
	while col > 0 do
		local c = line:sub(col + 1, col + 1)
		if not is_whitespace(c) then
			break
		end
		col = col - 1
	end

	-- Check if we're now on a prettified symbol
	local symbol = symbol_at(symbols, col)
	if symbol then
		vim.api.nvim_win_set_cursor(0, { row + 1, symbol.start_col })
		return
	end

	-- Find start of current word/punctuation sequence
	local char = line:sub(col + 1, col + 1)
	if is_word_char(char) then
		-- Go back to start of word
		while col > 0 do
			local prev_symbol = symbol_at(symbols, col - 1)
			if prev_symbol then
				break
			end
			local c = line:sub(col, col)
			if not is_word_char(c) then
				break
			end
			col = col - 1
		end
	elseif not is_whitespace(char) then
		-- Go back to start of punctuation
		while col > 0 do
			local prev_symbol = symbol_at(symbols, col - 1)
			if prev_symbol then
				break
			end
			local c = line:sub(col, col)
			if is_word_char(c) or is_whitespace(c) then
				break
			end
			col = col - 1
		end
	end

	-- If at start of line, use normal 'b' to go to previous line
	if col < 0 then
		vim.cmd("normal! b")
		return
	end

	vim.api.nvim_win_set_cursor(0, { row + 1, col })
end

---Move to end of word, treating prettified symbols as word boundaries
function M.move_word_end()
	local buf = vim.api.nvim_get_current_buf()
	local cursor = vim.api.nvim_win_get_cursor(0)
	local row = cursor[1] - 1 -- 0-indexed
	local col = cursor[2] -- 0-indexed

	local line = vim.api.nvim_buf_get_lines(buf, row, row + 1, false)[1]
	if not line or #line == 0 then
		vim.cmd("normal! e")
		return
	end

	local symbols = get_line_symbols(buf, row)
	-- If we're on a prettified symbol, skip past it first
	local current_symbol = symbol_at(symbols, col)
	if current_symbol then
		col = current_symbol.end_col
	else
		-- Move at least one position
		col = col + 1
	end

	-- Skip whitespace
	while col < #line do
		local c = line:sub(col + 1, col + 1)
		if not is_whitespace(c) then
			break
		end
		col = col + 1
	end

	-- If at end of line, use normal 'e' to go to next line
	if col >= #line then
		vim.cmd("normal! e")
		return
	end

	-- Check if we're now on a prettified symbol
	local symbol = symbol_at(symbols, col)
	if symbol then
		-- For concealed symbols, cursor on start_col visually appears "on" the symbol
		vim.api.nvim_win_set_cursor(0, { row + 1, symbol.start_col })
		return
	end

	-- Find end of current word/punctuation sequence
	local char = line:sub(col + 1, col + 1)
	if is_word_char(char) then
		while col < #line - 1 do
			local next_symbol = symbol_at(symbols, col + 1)
			if next_symbol then
				break
			end
			local c = line:sub(col + 2, col + 2)
			if not is_word_char(c) then
				break
			end
			col = col + 1
		end
	elseif not is_whitespace(char) then
		while col < #line - 1 do
			local next_symbol = symbol_at(symbols, col + 1)
			if next_symbol then
				break
			end
			local c = line:sub(col + 2, col + 2)
			if is_word_char(c) or is_whitespace(c) then
				break
			end
			col = col + 1
		end
	end

	vim.api.nvim_win_set_cursor(0, { row + 1, col })
end

---Delete character under cursor (or entire prettified symbol)
function M.delete_char()
	local buf = vim.api.nvim_get_current_buf()
	local cursor = vim.api.nvim_win_get_cursor(0)
	local row = cursor[1] - 1 -- 0-indexed
	local col = cursor[2] -- 0-indexed

	-- Check if we're on a prettified symbol
	local symbol = M.get_symbol_at(buf, row, col)

	if symbol then
		-- Delete the entire symbol text without replacing the whole line
		pcall(vim.api.nvim_buf_del_extmark, buf, state.ns, symbol.id)
		vim.api.nvim_buf_set_text(buf, row, symbol.start_col, row, symbol.end_col, { "" })
		-- Cursor stays at symbol.start_col or adjusts if at end of line
		vim.api.nvim_win_set_cursor(0, { row + 1, symbol.start_col })
	else
		-- Normal delete
		vim.cmd("normal! x")
	end
end

---Delete character before cursor (or entire prettified symbol before cursor)
function M.delete_char_before()
	local buf = vim.api.nvim_get_current_buf()
	local cursor = vim.api.nvim_win_get_cursor(0)
	local row = cursor[1] - 1 -- 0-indexed
	local col = cursor[2] -- 0-indexed

	if col == 0 then
		-- At start of line, normal X behavior
		vim.cmd("normal! X")
		return
	end

	-- Check if character before cursor is part of a prettified symbol
	local symbol = M.get_symbol_at(buf, row, col - 1)

	if symbol then
		-- Delete the entire symbol text without replacing the whole line
		pcall(vim.api.nvim_buf_del_extmark, buf, state.ns, symbol.id)
		vim.api.nvim_buf_set_text(buf, row, symbol.start_col, row, symbol.end_col, { "" })
		-- Move cursor to where symbol started
		local new_col = math.max(0, symbol.start_col)
		vim.api.nvim_win_set_cursor(0, { row + 1, new_col })
	else
		-- Normal delete before
		vim.cmd("normal! X")
	end
end

---Call original mapping fallback (e.g., mini-pairs)
---@param buf integer
---@param key string
---@return string
local function normalize_mapping_result(orig, result)
	if result == nil then
		return ""
	end
	if type(result) ~= "string" then
		result = tostring(result)
	end
	if result == "" then
		return ""
	end
	if orig.replace_keycodes == 1 or orig.replace_keycodes == true then
		return vim.api.nvim_replace_termcodes(result, true, false, true)
	end
	return result
end

local function call_original_mapping(buf, key)
	local orig = original_mappings[buf] and original_mappings[buf][key]
	if orig then
		if orig.callback then
			local ok, result = pcall(orig.callback)
			if ok then
				return normalize_mapping_result(orig, result)
			end
		elseif orig.rhs and orig.rhs ~= "" then
			if orig.expr == 1 then
				-- Original mapping is also expr, evaluate it
				local ok, result = pcall(vim.fn.eval, orig.rhs)
				if ok then
					return normalize_mapping_result(orig, result)
				end
			else
				-- Non-expr mapping, convert to terminal codes
				return vim.api.nvim_replace_termcodes(orig.rhs, true, false, true)
			end
		end
	end
	-- Default: convert key to terminal codes
	return vim.api.nvim_replace_termcodes(key, true, false, true)
end

---Backspace in insert mode: delete entire prettified symbol before cursor
---@return string
function M.insert_backspace()
	local buf = vim.api.nvim_get_current_buf()
	local cursor = vim.api.nvim_win_get_cursor(0)
	local row = cursor[1] - 1 -- 0-indexed
	local col = cursor[2] -- 0-indexed

	if col == 0 then
		return call_original_mapping(buf, "<BS>")
	end

	-- Check if character before cursor is part of a prettified symbol
	local symbol = M.get_symbol_at(buf, row, col - 1)

	if symbol then
		-- Return key sequence to delete full symbol without buffer edits in textlock
		local line = vim.api.nvim_buf_get_lines(buf, row, row + 1, false)[1] or ""
		local left = line:sub(symbol.start_col + 1, col)
		local right = line:sub(col + 1, symbol.end_col)
		local left_chars = vim.fn.strchars(left)
		local right_chars = vim.fn.strchars(right)
		-- Convert to terminal codes (replace_keycodes = false in keymap)
		local bs = vim.api.nvim_replace_termcodes("<BS>", true, false, true)
		local del = vim.api.nvim_replace_termcodes("<Del>", true, false, true)
		return string.rep(bs, left_chars) .. string.rep(del, right_chars)
	end

	return call_original_mapping(buf, "<BS>")
end

---Move cursor right in insert mode, treating prettified symbols as single chars (C-f)
---@return string
function M.insert_move_right()
	local buf = vim.api.nvim_get_current_buf()
	local cursor = vim.api.nvim_win_get_cursor(0)
	local row = cursor[1] - 1 -- 0-indexed
	local col = cursor[2] -- 0-indexed

	local line = vim.api.nvim_buf_get_lines(buf, row, row + 1, false)[1] or ""
	if col >= #line then
		return call_original_mapping(buf, "<C-f>")
	end

	-- Check if we're on a prettified symbol
	local symbol = M.get_symbol_at(buf, row, col)

	if symbol then
		-- Move to end of symbol: need (end_col - col) <Right> presses
		local chars_to_skip = vim.fn.strchars(line:sub(col + 1, symbol.end_col))
		local right = vim.api.nvim_replace_termcodes("<Right>", true, false, true)
		return string.rep(right, chars_to_skip)
	end

	return call_original_mapping(buf, "<C-f>")
end

---Move cursor left in insert mode, treating prettified symbols as single chars (C-b)
---@return string
function M.insert_move_left()
	local buf = vim.api.nvim_get_current_buf()
	local cursor = vim.api.nvim_win_get_cursor(0)
	local row = cursor[1] - 1 -- 0-indexed
	local col = cursor[2] -- 0-indexed

	if col == 0 then
		return call_original_mapping(buf, "<C-b>")
	end

	-- Check if character before cursor is part of a prettified symbol
	local symbol = M.get_symbol_at(buf, row, col - 1)

	if symbol then
		-- Move to start of symbol: need (col - start_col) <Left> presses
		local line = vim.api.nvim_buf_get_lines(buf, row, row + 1, false)[1] or ""
		local chars_to_skip = vim.fn.strchars(line:sub(symbol.start_col + 1, col))
		local left = vim.api.nvim_replace_termcodes("<Left>", true, false, true)
		return string.rep(left, chars_to_skip)
	end

	return call_original_mapping(buf, "<C-b>")
end

---Append after cursor (or after entire prettified symbol)
function M.append_after()
	local buf = vim.api.nvim_get_current_buf()
	local cursor = vim.api.nvim_win_get_cursor(0)
	local row = cursor[1] - 1 -- 0-indexed
	local col = cursor[2] -- 0-indexed

	-- Check if we're on a prettified symbol
	local symbol = M.get_symbol_at(buf, row, col)

	if symbol then
		-- Move cursor to end of symbol and enter insert mode
		vim.api.nvim_win_set_cursor(0, { row + 1, symbol.end_col })
		vim.cmd("startinsert")
	else
		-- Normal append: move cursor right and enter insert mode
		local line = vim.api.nvim_buf_get_lines(buf, row, row + 1, false)[1] or ""
		if #line == 0 then
			-- Empty line: just start insert
			vim.cmd("startinsert")
		else
			-- Move past current char and start insert
			vim.api.nvim_win_set_cursor(0, { row + 1, col + 1 })
			vim.cmd("startinsert")
		end
	end
end

---Substitute character under cursor (or entire prettified symbol) and enter insert mode
function M.substitute_char()
	local buf = vim.api.nvim_get_current_buf()
	local cursor = vim.api.nvim_win_get_cursor(0)
	local row = cursor[1] - 1 -- 0-indexed
	local col = cursor[2] -- 0-indexed

	-- Check if we're on a prettified symbol
	local symbol = M.get_symbol_at(buf, row, col)

	if symbol then
		-- Delete the entire symbol text and enter insert mode
		pcall(vim.api.nvim_buf_del_extmark, buf, state.ns, symbol.id)
		vim.api.nvim_buf_set_text(buf, row, symbol.start_col, row, symbol.end_col, { "" })
		-- Position cursor at symbol start and enter insert mode
		vim.api.nvim_win_set_cursor(0, { row + 1, symbol.start_col })
		vim.cmd("startinsert")
	else
		-- Normal substitute
		vim.cmd("normal! s")
	end
end

---Change operator function for use with motions
---This is called by operatorfunc after a motion is applied
---@param type string The type of motion: 'char', 'line', or 'block'
function M.change_opfunc(type)
	local buf = vim.api.nvim_get_current_buf()

	if type == "char" then
		-- Get the range marked by '[ and ']
		local start_pos = vim.api.nvim_buf_get_mark(buf, "[")
		local end_pos = vim.api.nvim_buf_get_mark(buf, "]")

		local start_row = start_pos[1] - 1 -- 0-indexed
		local start_col = start_pos[2]
		local end_row = end_pos[1] - 1
		local end_col = end_pos[2]

		-- Handle single-line change
		if start_row == end_row then
			-- Check if start position is on a prettified symbol
			local start_symbol = M.get_symbol_at(buf, start_row, start_col)
			if start_symbol and start_col > start_symbol.start_col then
				-- Expand start to include whole symbol
				start_col = start_symbol.start_col
			end

			-- Check if end position is on a prettified symbol
			local end_symbol = M.get_symbol_at(buf, end_row, end_col)
			if end_symbol then
				-- Expand end to include whole symbol
				end_col = end_symbol.end_col - 1
			end

			-- Delete the range and enter insert mode
			vim.api.nvim_buf_set_text(buf, start_row, start_col, end_row, end_col + 1, { "" })
			vim.api.nvim_win_set_cursor(0, { start_row + 1, start_col })
			vim.cmd("startinsert")
		else
			-- Multi-line change - use normal behavior
			vim.cmd('normal! `[v`]"_c')
		end
	elseif type == "line" then
		-- Line-wise change - use normal behavior
		vim.cmd('normal! `[V`]"_c')
	else
		-- Block change - use normal behavior
		vim.cmd('normal! `[\\<C-V>`]"_c')
	end
end

---Set up change operator and wait for motion
function M.change_operator()
	vim.o.operatorfunc = "v:lua.require'sigil.motions'.change_opfunc"
	return "g@"
end

---Change current line (restore built-in cc behavior)
function M.change_line()
	local count = vim.v.count1
	local keys = vim.api.nvim_replace_termcodes(tostring(count) .. "cc", true, false, true)
	vim.api.nvim_feedkeys(keys, "nt", false)
end

-- ============================================
-- Visual Mode Support (4.6)
-- ============================================

---Get the visual selection range
---@return integer, integer, integer, integer start_row, start_col, end_row, end_col (0-indexed)
local function get_visual_range()
	local start_pos = vim.fn.getpos("v")
	local end_pos = vim.fn.getpos(".")

	local start_row = start_pos[2] - 1
	local start_col = start_pos[3] - 1
	local end_row = end_pos[2] - 1
	local end_col = end_pos[3] - 1

	-- Ensure start is before end
	if start_row > end_row or (start_row == end_row and start_col > end_col) then
		start_row, end_row = end_row, start_row
		start_col, end_col = end_col, start_col
	end

	return start_row, start_col, end_row, end_col
end

---Expand visual selection to include full prettified symbols at boundaries
---@param buf integer
---@param start_row integer 0-indexed
---@param start_col integer 0-indexed
---@param end_row integer 0-indexed
---@param end_col integer 0-indexed
---@return integer, integer, integer, integer Expanded range
local function expand_selection_to_symbols(buf, start_row, start_col, end_row, end_col)
	-- Check if start is inside a prettified symbol
	local start_symbol = M.get_symbol_at(buf, start_row, start_col)
	if start_symbol and start_col > start_symbol.start_col then
		start_col = start_symbol.start_col
	end

	-- Check if end is inside a prettified symbol
	local end_symbol = M.get_symbol_at(buf, end_row, end_col)
	if end_symbol and end_col < end_symbol.end_col - 1 then
		end_col = end_symbol.end_col - 1
	end

	return start_row, start_col, end_row, end_col
end

---Move cursor right in visual mode, treating prettified symbols as single chars
function M.visual_move_right()
	local buf = vim.api.nvim_get_current_buf()
	local cursor = vim.api.nvim_win_get_cursor(0)
	local row = cursor[1] - 1 -- 0-indexed
	local col = cursor[2] -- 0-indexed

	local line = vim.api.nvim_buf_get_lines(buf, row, row + 1, false)[1]
	if not line then
		vim.cmd("normal! l")
		return
	end

	-- Check if we're on a prettified symbol
	local symbols = get_line_symbols(buf, row)
	local symbol = symbol_at(symbols, col)

	if symbol then
		-- On a symbol: move past it (to end_col)
		if symbol.end_col < #line then
			vim.api.nvim_win_set_cursor(0, { row + 1, symbol.end_col })
		else
			vim.cmd("normal! l")
		end
	else
		-- Not on a symbol: normal movement (will land on symbol start if next char is symbol)
		vim.cmd("normal! l")
	end
end

---Move cursor left in visual mode, treating prettified symbols as single chars
function M.visual_move_left()
	local buf = vim.api.nvim_get_current_buf()
	local cursor = vim.api.nvim_win_get_cursor(0)
	local row = cursor[1] - 1 -- 0-indexed
	local col = cursor[2] -- 0-indexed

	-- Check if we're on a prettified symbol (not at its start)
	local symbols = get_line_symbols(buf, row)
	local symbol = symbol_at(symbols, col)

	if symbol and col > symbol.start_col then
		-- Move to start of symbol
		vim.api.nvim_win_set_cursor(0, { row + 1, symbol.start_col })
	elseif col > 0 then
		-- Check if position to the left is part of a symbol
		local prev_symbol = symbol_at(symbols, col - 1)

		if prev_symbol then
			-- Move to start of that symbol
			vim.api.nvim_win_set_cursor(0, { row + 1, prev_symbol.start_col })
		else
			vim.cmd("normal! h")
		end
	else
		vim.cmd("normal! h")
	end
end

---Move to next word in visual mode, treating prettified symbols as boundaries
function M.visual_move_word_forward()
	local buf = vim.api.nvim_get_current_buf()
	local cursor = vim.api.nvim_win_get_cursor(0)
	local row = cursor[1] - 1 -- 0-indexed
	local col = cursor[2] -- 0-indexed

	local line = vim.api.nvim_buf_get_lines(buf, row, row + 1, false)[1]
	if not line or #line == 0 then
		vim.cmd("normal! w")
		return
	end

	local symbols = get_line_symbols(buf, row)
	-- If we're on a prettified symbol, skip to end of it first
	local symbol = symbol_at(symbols, col)
	if symbol then
		col = symbol.end_col
	else
		-- Skip current word
		local char = line:sub(col + 1, col + 1)
		if is_word_char(char) then
			while col < #line do
				local next_symbol = symbol_at(symbols, col)
				if next_symbol then
					col = next_symbol.end_col
					break
				end
				local c = line:sub(col + 1, col + 1)
				if not is_word_char(c) then
					break
				end
				col = col + 1
			end
		elseif not is_whitespace(char) then
			while col < #line do
				local next_symbol = symbol_at(symbols, col)
				if next_symbol then
					col = next_symbol.end_col
					break
				end
				local c = line:sub(col + 1, col + 1)
				if is_word_char(c) or is_whitespace(c) then
					break
				end
				col = col + 1
			end
		end
	end

	-- Skip whitespace
	while col < #line do
		local c = line:sub(col + 1, col + 1)
		if not is_whitespace(c) then
			break
		end
		col = col + 1
	end

	if col >= #line then
		vim.cmd("normal! w")
		return
	end

	vim.api.nvim_win_set_cursor(0, { row + 1, col })
end

---Move to previous word in visual mode, treating prettified symbols as boundaries
function M.visual_move_word_backward()
	local buf = vim.api.nvim_get_current_buf()
	local cursor = vim.api.nvim_win_get_cursor(0)
	local row = cursor[1] - 1 -- 0-indexed
	local col = cursor[2] -- 0-indexed

	local line = vim.api.nvim_buf_get_lines(buf, row, row + 1, false)[1]
	if not line or col == 0 then
		vim.cmd("normal! b")
		return
	end

	local symbols = get_line_symbols(buf, row)
	-- Move one position left first
	col = col - 1

	-- Skip whitespace going backward
	while col > 0 do
		local c = line:sub(col + 1, col + 1)
		if not is_whitespace(c) then
			break
		end
		col = col - 1
	end

	-- Check if we're now on a prettified symbol
	local symbol = symbol_at(symbols, col)
	if symbol then
		vim.api.nvim_win_set_cursor(0, { row + 1, symbol.start_col })
		return
	end

	-- Find start of current word/punctuation sequence
	local char = line:sub(col + 1, col + 1)
	if is_word_char(char) then
		while col > 0 do
			local prev_symbol = symbol_at(symbols, col - 1)
			if prev_symbol then
				break
			end
			local c = line:sub(col, col)
			if not is_word_char(c) then
				break
			end
			col = col - 1
		end
	elseif not is_whitespace(char) then
		while col > 0 do
			local prev_symbol = symbol_at(symbols, col - 1)
			if prev_symbol then
				break
			end
			local c = line:sub(col, col)
			if is_word_char(c) or is_whitespace(c) then
				break
			end
			col = col - 1
		end
	end

	if col < 0 then
		vim.cmd("normal! b")
		return
	end

	vim.api.nvim_win_set_cursor(0, { row + 1, col })
end

---Move to end of word in visual mode, treating prettified symbols as boundaries
function M.visual_move_word_end()
	local buf = vim.api.nvim_get_current_buf()
	local cursor = vim.api.nvim_win_get_cursor(0)
	local row = cursor[1] - 1 -- 0-indexed
	local col = cursor[2] -- 0-indexed

	local line = vim.api.nvim_buf_get_lines(buf, row, row + 1, false)[1]
	if not line or #line == 0 then
		vim.cmd("normal! e")
		return
	end

	local symbols = get_line_symbols(buf, row)
	-- If we're on a prettified symbol, skip past it first
	local current_symbol = symbol_at(symbols, col)
	if current_symbol then
		col = current_symbol.end_col
	else
		col = col + 1
	end

	-- Skip whitespace
	while col < #line do
		local c = line:sub(col + 1, col + 1)
		if not is_whitespace(c) then
			break
		end
		col = col + 1
	end

	if col >= #line then
		vim.cmd("normal! e")
		return
	end

	-- Check if we're now on a prettified symbol
	local symbol = symbol_at(symbols, col)
	if symbol then
		-- In visual mode, position at end of symbol (end_col - 1)
		vim.api.nvim_win_set_cursor(0, { row + 1, symbol.end_col - 1 })
		return
	end

	-- Find end of current word/punctuation sequence
	local char = line:sub(col + 1, col + 1)
	if is_word_char(char) then
		while col < #line - 1 do
			local next_symbol = symbol_at(symbols, col + 1)
			if next_symbol then
				break
			end
			local c = line:sub(col + 2, col + 2)
			if not is_word_char(c) then
				break
			end
			col = col + 1
		end
	elseif not is_whitespace(char) then
		while col < #line - 1 do
			local next_symbol = symbol_at(symbols, col + 1)
			if next_symbol then
				break
			end
			local c = line:sub(col + 2, col + 2)
			if is_word_char(c) or is_whitespace(c) then
				break
			end
			col = col + 1
		end
	end

	vim.api.nvim_win_set_cursor(0, { row + 1, col })
end

---Adjust visual selection to include full prettified symbols
---Called after standard visual operations (d, y, c) via operatorfunc
function M.visual_adjust_selection()
	local buf = vim.api.nvim_get_current_buf()
	local mode = vim.fn.mode()

	if mode ~= "v" and mode ~= "V" and mode ~= "\22" then
		return
	end

	local start_row, start_col, end_row, end_col = get_visual_range()
	local new_start_row, new_start_col, new_end_row, new_end_col =
		expand_selection_to_symbols(buf, start_row, start_col, end_row, end_col)

	-- If selection was expanded, update it
	if new_start_col ~= start_col or new_end_col ~= end_col then
		-- Exit visual mode and reselect with new range
		vim.cmd("normal! \\<Esc>")
		vim.api.nvim_win_set_cursor(0, { new_start_row + 1, new_start_col })
		vim.cmd("normal! v")
		vim.api.nvim_win_set_cursor(0, { new_end_row + 1, new_end_col })
	end
end

---Save original mapping before overriding (supports both buffer-local and global mappings)
---@param buf integer
---@param mode string
---@param key string
local function save_original_mapping(buf, mode, key)
	local existing = vim.fn.maparg(key, mode, false, true)
	if existing and next(existing) ~= nil then
		original_mappings[buf] = original_mappings[buf] or {}
		original_mappings[buf][key] = existing
	end
end

---Setup keymaps for atomic symbol motions
---@param buf integer
function M.setup_keymaps(buf)
	local opts = { buffer = buf, silent = true }

	-- Save original insert mode mappings before overriding (for mini-pairs compatibility)
	save_original_mapping(buf, "i", "<BS>")
	save_original_mapping(buf, "i", "<C-f>")
	save_original_mapping(buf, "i", "<C-b>")

	-- Character motions (normal mode)
	vim.keymap.set("n", "l", M.move_right, opts)
	vim.keymap.set("n", "h", M.move_left, opts)
	vim.keymap.set("n", "j", M.move_down, opts)
	vim.keymap.set("n", "k", M.move_up, opts)

	-- Word motions (normal mode)
	vim.keymap.set("n", "w", M.move_word_forward, opts)
	vim.keymap.set("n", "b", M.move_word_backward, opts)
	vim.keymap.set("n", "e", M.move_word_end, opts)

	-- Delete operations
	vim.keymap.set("n", "x", M.delete_char, opts)
	vim.keymap.set("n", "X", M.delete_char_before, opts)
	vim.keymap.set(
		"i",
		"<BS>",
		M.insert_backspace,
		{ buffer = buf, silent = true, expr = true, replace_keycodes = false }
	)
	vim.keymap.set(
		"i",
		"<C-f>",
		M.insert_move_right,
		{ buffer = buf, silent = true, expr = true, replace_keycodes = false }
	)
	vim.keymap.set(
		"i",
		"<C-b>",
		M.insert_move_left,
		{ buffer = buf, silent = true, expr = true, replace_keycodes = false }
	)

	-- Change/insert operations
	vim.keymap.set("n", "s", M.substitute_char, opts)
	vim.keymap.set("n", "a", M.append_after, opts)
	vim.keymap.set("n", "c", M.change_operator, { buffer = buf, silent = true, expr = true })
	vim.keymap.set("n", "cc", M.change_line, opts)

	-- Visual mode motions (4.6)
	vim.keymap.set("x", "l", M.visual_move_right, opts)
	vim.keymap.set("x", "h", M.visual_move_left, opts)
	vim.keymap.set("x", "w", M.visual_move_word_forward, opts)
	vim.keymap.set("x", "b", M.visual_move_word_backward, opts)
	vim.keymap.set("x", "e", M.visual_move_word_end, opts)
	vim.keymap.set("x", "j", M.move_down, opts)
	vim.keymap.set("x", "k", M.move_up, opts)
end

---Remove keymaps for atomic symbol motions
---@param buf integer
function M.remove_keymaps(buf)
	-- Character motions (normal mode)
	pcall(vim.keymap.del, "n", "l", { buffer = buf })
	pcall(vim.keymap.del, "n", "h", { buffer = buf })
	pcall(vim.keymap.del, "n", "j", { buffer = buf })
	pcall(vim.keymap.del, "n", "k", { buffer = buf })

	-- Word motions (normal mode)
	pcall(vim.keymap.del, "n", "w", { buffer = buf })
	pcall(vim.keymap.del, "n", "b", { buffer = buf })
	pcall(vim.keymap.del, "n", "e", { buffer = buf })

	-- Delete operations
	pcall(vim.keymap.del, "n", "x", { buffer = buf })
	pcall(vim.keymap.del, "n", "X", { buffer = buf })
	pcall(vim.keymap.del, "i", "<BS>", { buffer = buf })
	pcall(vim.keymap.del, "i", "<C-f>", { buffer = buf })
	pcall(vim.keymap.del, "i", "<C-b>", { buffer = buf })

	-- Change/insert operations
	pcall(vim.keymap.del, "n", "s", { buffer = buf })
	pcall(vim.keymap.del, "n", "a", { buffer = buf })
	pcall(vim.keymap.del, "n", "c", { buffer = buf })
	pcall(vim.keymap.del, "n", "cc", { buffer = buf })

	-- Visual mode motions (4.6)
	pcall(vim.keymap.del, "x", "l", { buffer = buf })
	pcall(vim.keymap.del, "x", "h", { buffer = buf })
	pcall(vim.keymap.del, "x", "w", { buffer = buf })
	pcall(vim.keymap.del, "x", "b", { buffer = buf })
	pcall(vim.keymap.del, "x", "e", { buffer = buf })
	pcall(vim.keymap.del, "x", "j", { buffer = buf })
	pcall(vim.keymap.del, "x", "k", { buffer = buf })

	-- Clear saved original mappings for this buffer
	original_mappings[buf] = nil
end

return M
