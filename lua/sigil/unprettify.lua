-- sigil.nvim - Unprettify at point module
-- Shows original text when cursor is on a prettified symbol or line

local state = require("sigil.state")
local config = require("sigil.config")

local M = {}

---@class sigil.UnprettifySymbol
---@field id integer Extmark ID
---@field row integer 0-indexed row
---@field col integer 0-indexed start column
---@field end_col integer 0-indexed end column
---@field replacement string Original replacement character
---@field hl_group? string Highlight group for the replacement

---@class sigil.UnprettifyState
---@field mode "symbol"|"line" What kind of unprettify is active
---@field row integer 0-indexed row of unprettified content
---@field symbols sigil.UnprettifySymbol[] List of unprettified symbols

---Per-buffer state tracking what is currently unprettified
---@type table<integer, sigil.UnprettifyState|nil>
M._state = {}

---Extract replacement character and hl_group from extmark details
---@param details table Extmark details
---@return string|nil replacement Replacement character
---@return string|nil hl_group Highlight group
local function get_replacement(details)
	if details.virt_text and #details.virt_text > 0 then
		return details.virt_text[1][1], details.virt_text[1][2]
	elseif details.conceal and details.conceal ~= "" and details.conceal ~= " " then
		return details.conceal, nil
	end
	return nil, nil
end

---Restore all unprettified symbols
---@param buf integer
local function restore_symbols(buf)
	local s = M._state[buf]
	if not s then
		return
	end

	if not vim.api.nvim_buf_is_valid(buf) then
		M._state[buf] = nil
		return
	end

	for _, sym in ipairs(s.symbols) do
		-- Check if extmark still exists
		local ok, marks = pcall(vim.api.nvim_buf_get_extmarks, buf, state.ns, sym.id, sym.id, { details = true })
		if ok and #marks > 0 then
			local mark = marks[1]
			local row = mark[2]
			local col = mark[3]
			local end_col = mark[4].end_col or (col + 1)

			local virt_text_entry = sym.hl_group and { sym.replacement, sym.hl_group } or { sym.replacement }
			pcall(vim.api.nvim_buf_set_extmark, buf, state.ns, row, col, {
				id = sym.id,
				end_col = end_col,
				conceal = " ",
				virt_text = { virt_text_entry },
				virt_text_pos = "overlay",
				virt_text_hide = false,
				hl_mode = "combine",
				priority = 100,
			})
		end
	end

	M._state[buf] = nil
end

---Hide a single symbol (remove conceal and virt_text)
---@param buf integer
---@param id integer Extmark ID
---@param row integer
---@param col integer
---@param end_col integer
local function hide_extmark(buf, id, row, col, end_col)
	pcall(vim.api.nvim_buf_set_extmark, buf, state.ns, row, col, {
		id = id,
		end_col = end_col,
		priority = 100,
	})
end

---Get all prettified symbols on a line
---@param buf integer
---@param row integer 0-indexed row
---@return sigil.UnprettifySymbol[]
local function get_line_symbols(buf, row)
	local marks = vim.api.nvim_buf_get_extmarks(buf, state.ns, { row, 0 }, { row, -1 }, { details = true })
	local symbols = {}

	for _, mark in ipairs(marks) do
		local col = mark[3]
		local end_col = mark[4].end_col or (col + 1)
		local replacement, hl_group = get_replacement(mark[4])

		if replacement and end_col > col then
			table.insert(symbols, {
				id = mark[1],
				row = mark[2],
				col = col,
				end_col = end_col,
				replacement = replacement,
				hl_group = hl_group,
			})
		end
	end

	return symbols
end

---Check if ALL tracked extmarks still exist
---@param buf integer
---@param tracked_state sigil.UnprettifyState
---@return boolean
local function state_is_valid(buf, tracked_state)
	if #tracked_state.symbols == 0 then
		return false
	end
	for _, sym in ipairs(tracked_state.symbols) do
		local ok, marks = pcall(vim.api.nvim_buf_get_extmarks, buf, state.ns, sym.id, sym.id, {})
		if not ok or #marks == 0 then
			return false
		end
	end
	return true
end

---Update for "symbol" mode (unprettify single symbol under cursor)
---@param buf integer
---@param row integer
---@param col integer
local function update_symbol_mode(buf, row, col)
	local current = M._state[buf]

	if current then
		if not state_is_valid(buf, current) then
			M._state[buf] = nil
		elseif current.row == row then
			-- Check if cursor is still on the unprettified symbol
			local sym = current.symbols[1]
			if sym and col >= sym.col and col < sym.end_col then
				return -- still on it
			end
		end
		-- Cursor moved away or state invalid
		if M._state[buf] then
			restore_symbols(buf)
		end
	end

	-- Find symbol at cursor
	local symbols = get_line_symbols(buf, row)
	for _, sym in ipairs(symbols) do
		if col >= sym.col and col < sym.end_col then
			hide_extmark(buf, sym.id, sym.row, sym.col, sym.end_col)
			M._state[buf] = {
				mode = "symbol",
				row = row,
				symbols = { sym },
			}
			return
		end
	end
end

---Update for "line" mode (unprettify all symbols on cursor line)
---@param buf integer
---@param row integer
local function update_line_mode(buf, row)
	local current = M._state[buf]

	if current then
		if current.row == row then
			-- Same line — check if state is still valid
			if state_is_valid(buf, current) then
				return -- still on the same line, nothing to do
			end
			-- State is stale (extmarks recreated), restore surviving ones then re-scan
			restore_symbols(buf)
		else
			-- Different line, restore old line
			restore_symbols(buf)
		end
	end

	-- Find all symbols on cursor line
	local symbols = get_line_symbols(buf, row)
	if #symbols == 0 then
		return
	end

	-- Hide all symbols on this line
	for _, sym in ipairs(symbols) do
		hide_extmark(buf, sym.id, sym.row, sym.col, sym.end_col)
	end

	M._state[buf] = {
		mode = "line",
		row = row,
		symbols = symbols,
	}
end

---Update unprettify state based on cursor position
---Called on CursorMoved/CursorMovedI
---@param buf integer
function M.update(buf)
	local opt = config.current.unprettify_at_point
	if not opt then
		return
	end

	if not state.is_enabled(buf) then
		restore_symbols(buf)
		return
	end

	local cursor = vim.api.nvim_win_get_cursor(0)
	local row = cursor[1] - 1
	local col = cursor[2]

	if opt == "line" then
		update_line_mode(buf, row)
	else
		-- opt == true: single symbol mode
		update_symbol_mode(buf, row, col)
	end
end

---Clear unprettify state for a buffer (called on detach)
---@param buf integer
function M.clear(buf)
	restore_symbols(buf)
	M._state[buf] = nil
end

return M
