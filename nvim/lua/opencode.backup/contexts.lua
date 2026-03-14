local M = {}

---@type table<string, fun():string>
local default_contexts = {
  ---@this - Operator range or visual selection if any, else cursor position
  ["@this"] = function()
    local mode = vim.fn.mode()
    
    if mode == "v" or mode == "V" or mode == "\22" then
      -- Visual selection
      local start_pos = vim.fn.getpos("'<")
      local end_pos = vim.fn.getpos("'>")
      local lines = vim.api.nvim_buf_get_lines(0, start_pos[2] - 1, end_pos[2], false)
      
      if #lines > 0 then
        -- Handle partial line selection
        if start_pos[2] == end_pos[2] then
          lines[1] = lines[1]:sub(start_pos[3], end_pos[3])
        else
          lines[1] = lines[1]:sub(start_pos[3])
          lines[#lines] = lines[#lines]:sub(1, end_pos[3])
        end
        
        return table.concat(lines, "\n")
      end
    end
    
    -- Default to cursor position with surrounding context
    local cursor = vim.api.nvim_win_get_cursor(0)
    local line = cursor[1]
    local col = cursor[2]
    local bufnr = vim.api.nvim_get_current_buf()
    
    -- Get some context around cursor
    local start_line = math.max(1, line - 5)
    local end_line = math.min(vim.api.nvim_buf_line_count(bufnr), line + 5)
    local lines = vim.api.nvim_buf_get_lines(bufnr, start_line - 1, end_line, false)
    
    return string.format("Line %d, Column %d:\n%s", line, col, table.concat(lines, "\n"))
  end,
  
  ---@buffer - Current buffer
  ["@buffer"] = function()
    local bufnr = vim.api.nvim_get_current_buf()
    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    local filename = vim.api.nvim_buf_get_name(bufnr)
    
    return string.format("File: %s\n```\n%s\n```", filename, table.concat(lines, "\n"))
  end,
  
  ---@buffers - Open buffers
  ["@buffers"] = function()
    local bufs = vim.api.nvim_list_bufs()
    local result = {}
    
    for _, bufnr in ipairs(bufs) do
      if vim.api.nvim_buf_is_loaded(bufnr) then
        local filename = vim.api.nvim_buf_get_name(bufnr)
        if filename ~= "" then
          table.insert(result, filename)
        end
      end
    end
    
    return "Open buffers:\n" .. table.concat(result, "\n")
  end,
  
  ---@visible - Visible text
  ["@visible"] = function()
    local bufnr = vim.api.nvim_get_current_buf()
    local start_line = vim.fn.line("w0")
    local end_line = vim.fn.line("w$")
    local lines = vim.api.nvim_buf_get_lines(bufnr, start_line - 1, end_line, false)
    
    return table.concat(lines, "\n")
  end,
  
  ---@diagnostics - Current buffer diagnostics
  ["@diagnostics"] = function()
    local bufnr = vim.api.nvim_get_current_buf()
    local diagnostics = vim.diagnostic.get(bufnr)
    
    if #diagnostics == 0 then
      return "No diagnostics"
    end
    
    local result = {}
    for _, d in ipairs(diagnostics) do
      local severity = vim.diagnostic.severity[d.severity] or "UNKNOWN"
      table.insert(result, string.format(
        "Line %d, Col %d [%s]: %s",
        d.lnum + 1,
        d.col + 1,
        severity,
        d.message
      ))
    end
    
    return "Diagnostics:\n" .. table.concat(result, "\n")
  end,
  
  ---@quickfix - Quickfix list
  ["@quickfix"] = function()
    local qflist = vim.fn.getqflist()
    
    if #qflist == 0 then
      return "Quickfix list is empty"
    end
    
    local result = {}
    for _, item in ipairs(qflist) do
      local bufname = item.bufnr and vim.fn.bufname(item.bufnr) or ""
      table.insert(result, string.format(
        "%s:%d:%d: %s",
        bufname,
        item.lnum,
        item.col,
        item.text or ""
      ))
    end
    
    return "Quickfix list:\n" .. table.concat(result, "\n")
  end,
  
  ---@diff - Git diff
  ["@diff"] = function()
    local handle = io.popen("git diff --no-color 2>/dev/null")
    if not handle then
      return "Unable to get git diff"
    end
    
    local result = handle:read("*a")
    handle:close()
    
    if result == "" then
      return "No changes (git diff is empty)"
    end
    
    return "```diff\n" .. result .. "\n```"
  end,
  
  ---@marks - Global marks
  ["@marks"] = function()
    local marks = vim.fn.getmarklist()
    local result = {}
    
    for _, mark in ipairs(marks) do
      if mark.mark:match("^'[A-Z]$") then
        local bufname = mark.bufnr and vim.fn.bufname(mark.bufnr) or ""
        table.insert(result, string.format(
          "%s: %s:%d:%d",
          mark.mark,
          bufname,
          mark.pos[2],
          mark.pos[3]
        ))
      end
    end
    
    if #result == 0 then
      return "No global marks set"
    end
    
    return "Global marks:\n" .. table.concat(result, "\n")
  end,
  
  ---@grapple - grapple.nvim tags
  ["@grapple"] = function()
    local has_grapple, grapple = pcall(require, "grapple")
    if not has_grapple then
      return "grapple.nvim is not installed"
    end
    
    local tags = grapple.tags()
    if not tags or #tags == 0 then
      return "No grapple tags"
    end
    
    local result = {}
    for _, tag in ipairs(tags) do
      table.insert(result, string.format(
        "%s: %s",
        tag.name or "unnamed",
        tag.path or ""
      ))
    end
    
    return "Grapple tags:\n" .. table.concat(result, "\n")
  end,
}

---Get all available contexts
---@return table<string, fun():string>
function M.get_all()
  local config = require("opencode.config")
  return vim.tbl_extend("force", {}, default_contexts, config.options.contexts or {})
end

---Inject context values into a prompt
---@param prompt string
---@return string
function M.inject(prompt)
  local all_contexts = M.get_all()
  
  for name, fn in pairs(all_contexts) do
    if prompt:find(name, 1, true) then
      local ok, value = pcall(fn)
      if ok then
        prompt = prompt:gsub(vim.pesc(name), value)
      else
        vim.notify(string.format("Error getting context %s: %s", name, value), vim.log.levels.WARN)
      end
    end
  end
  
  return prompt
end

return M
