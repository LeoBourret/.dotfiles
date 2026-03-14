local config = require("opencode.config")
local client = require("opencode.client")
local contexts = require("opencode.contexts")
local provider = require("opencode.provider")

local M = {}

-- Store recent asks for history
local ask_history = {}

---Setup the plugin
---@param opts? opencode.Opts
function M.setup(opts)
  config.setup(opts)
  
  -- Setup autocommands for events
  if config.options.events.reload then
    vim.api.nvim_create_autocmd("User", {
      pattern = "OpencodeEvent:file.edit",
      callback = function(args)
        local event = args.data.event
        if event and event.file then
          local bufnr = vim.fn.bufnr(event.file)
          if bufnr ~= -1 then
            vim.api.nvim_buf_call(bufnr, function()
              vim.cmd("checktime")
            end)
          end
        end
      end,
    })
  end
  
  -- Setup permission handling
  if config.options.events.permissions then
    local pending_permissions = {}
    
    vim.api.nvim_create_autocmd("User", {
      pattern = "OpencodeEvent:permission.request",
      callback = function(args)
        local event = args.data.event
        if event and event.id then
          pending_permissions[event.id] = event
        end
      end,
    })
    
    vim.api.nvim_create_autocmd("User", {
      pattern = "OpencodeEvent:session.idle",
      callback = function()
        for id, perm in pairs(pending_permissions) do
          local choice = vim.fn.confirm(
            string.format("Allow opencode to %s?", perm.action or "perform action"),
            "&Yes\n&No",
            1
          )
          
          client.send_permission_response(id, choice == 1)
          pending_permissions[id] = nil
        end
      end,
    })
  end
  
  -- Start event polling
  client.start_polling()
end

---Ask opencode with a prompt
---@param prompt? string Initial prompt text
---@param opts? { submit?: boolean }
function M.ask(prompt, opts)
  opts = opts or {}
  prompt = prompt or ""
  
  local function submit(input)
    if input and input ~= "" then
      table.insert(ask_history, 1, input)
      if #ask_history > (config.options.ask.history_size or 50) then
        table.remove(ask_history)
      end
      M.prompt(input)
    end
  end
  
  -- Use snacks.input if available
  local has_snacks, snacks = pcall(require, "snacks.input")
  if has_snacks then
    snacks.input({
      prompt = "Ask opencode: ",
      default = prompt,
      completion = config.options.ask.completions and "customlist,v:lua.require'opencode'.complete_ask" or nil,
    }, function(input)
      if input then
        submit(input)
      end
    end)
  else
    -- Fallback to vim.ui.input
    vim.ui.input({
      prompt = "Ask opencode: ",
      default = prompt,
      completion = config.options.ask.completions and "customlist,v:lua.require'opencode'.complete_ask" or nil,
    }, function(input)
      if input then
        submit(input)
      end
    end)
  end
end

---Get completions for ask input
---@param arglead string
---@param cmdline string
---@param cursorpos number
---@return string[]
function M.complete_ask(arglead, cmdline, cursorpos)
  local completions = {}
  
  -- Add context completions
  for name, _ in pairs(contexts.get_all()) do
    if name:match("^@" .. arglead:sub(2)) then
      table.insert(completions, name)
    end
  end
  
  -- Add history completions
  for _, hist in ipairs(ask_history) do
    if hist:match("^" .. vim.pesc(arglead)) then
      table.insert(completions, hist)
    end
  end
  
  return completions
end

---Select from opencode functionality
function M.select()
  local items = {}
  
  -- Add prompts
  for name, prompt in pairs(config.options.prompts) do
    table.insert(items, {
      text = string.format("Prompt: %s", name),
      prompt = prompt,
    })
  end
  
  -- Add commands
  local commands = {
    "session.list",
    "session.new",
    "session.select",
    "session.share",
    "session.interrupt",
    "session.compact",
    "session.page.up",
    "session.page.down",
    "session.half.page.up",
    "session.half.page.down",
    "session.first",
    "session.last",
    "session.undo",
    "session.redo",
    "prompt.submit",
    "prompt.clear",
    "agent.cycle",
  }
  
  for _, cmd in ipairs(commands) do
    table.insert(items, {
      text = string.format("Command: %s", cmd),
      command = cmd,
    })
  end
  
  -- Add provider controls
  table.insert(items, { text = "Provider: Toggle", action = "toggle" })
  table.insert(items, { text = "Provider: Start", action = "start" })
  table.insert(items, { text = "Provider: Stop", action = "stop" })
  
  -- Use snacks.picker if available
  local has_snacks, snacks = pcall(require, "snacks.picker")
  if has_snacks then
    snacks.pick({
      source = "opencode",
      items = items,
      format = function(item)
        return { { item.text, "SnacksPickerLabel" } }
      end,
      confirm = function(picker, item)
        picker:close()
        if item.prompt then
          M.prompt(item.prompt)
        elseif item.command then
          M.command(item.command)
        elseif item.action then
          if item.action == "toggle" then
            M.toggle()
          elseif item.action == "start" then
            provider.start()
          elseif item.action == "stop" then
            provider.stop()
          end
        end
      end,
    })
  else
    -- Fallback to vim.ui.select
    vim.ui.select(items, {
      prompt = "Select opencode action:",
      format_item = function(item)
        return item.text
      end,
    }, function(item)
      if item then
        if item.prompt then
          M.prompt(item.prompt)
        elseif item.command then
          M.command(item.command)
        elseif item.action then
          if item.action == "toggle" then
            M.toggle()
          elseif item.action == "start" then
            provider.start()
          elseif item.action == "stop" then
            provider.stop()
          end
        end
      end
    end)
  end
end

---Prompt opencode with text
---@param prompt string The prompt text
function M.prompt(prompt)
  -- Resolve named prompts
  if config.options.prompts[prompt] then
    prompt = config.options.prompts[prompt]
  end
  
  -- Inject contexts
  prompt = contexts.inject(prompt)
  
  -- Send to opencode
  client.send_prompt(prompt)
end

---Create an operator function
---@param prefix? string Text to prefix the selection with
---@return function
function M.operator(prefix)
  prefix = prefix or "@this "
  
  return function()
    local mode = vim.fn.mode()
    local start_pos, end_pos
    
    if mode == "v" or mode == "V" or mode == "\22" then
      -- Visual mode
      start_pos = vim.fn.getpos("'<")
      end_pos = vim.fn.getpos("'>")
    else
      -- Normal mode - wait for motion
      vim.opt.operatorfunc = "v:lua.require'opencode'.operator_callback"
      return "g@"
    end
    
    -- Get the selected text
    local lines = vim.api.nvim_buf_get_lines(0, start_pos[2] - 1, end_pos[2], false)
    local text = table.concat(lines, "\n")
    
    -- Prompt with the selected text
    M.prompt(prefix .. text)
  end
end

---Operator callback for dot-repeat support
---@param motion string
function M.operator_callback(motion)
  local start_pos = vim.fn.getpos("'[")
  local end_pos = vim.fn.getpos("']")
  
  local lines = vim.api.nvim_buf_get_lines(0, start_pos[2] - 1, end_pos[2], false)
  local text = table.concat(lines, "\n")
  
  M.prompt("@this " .. text)
end

---Send a command to opencode
---@param command string The command to send
function M.command(command)
  client.send_command(command)
end

---Toggle the opencode provider
function M.toggle()
  provider.toggle()
end

---Get statusline component
---@return string
function M.statusline()
  local status = client.get_status()
  if config.options.statusline.format then
    return config.options.statusline.format(status)
  end
  return ""
end

return M
