local config = require("opencode.config")

local M = {}

local current_provider = nil

---Detect which provider to use
---@return string provider_name
function M.detect_provider()
  local opts = config.options.provider
  
  if opts.enabled and opts.enabled ~= "auto" then
    return opts.enabled
  end
  
  -- Auto-detect based on availability
  if vim.fn.executable("tmux") == 1 and vim.env.TMUX then
    return "tmux"
  elseif vim.fn.executable("kitty") == 1 and vim.env.KITTY_PID then
    return "kitty"
  elseif vim.fn.executable("wezterm") == 1 and vim.env.WEZTERM_EXECUTABLE then
    return "wezterm"
  else
    -- Check if snacks is available
    local has_snacks, _ = pcall(require, "snacks.terminal")
    if has_snacks then
      return "snacks"
    else
      return "terminal"
    end
  end
end

---Get a free port
---@return number
function M.get_free_port()
  -- Try to find a free port
  for port = 3000, 3010 do
    local handle = io.popen(string.format("lsof -i:%d 2>/dev/null | wc -l", port))
    if handle then
      local result = handle:read("*a")
      handle:close()
      if tonumber(result) == 0 then
        return port
      end
    end
  end
  return 3000
end

---Build the opencode command
---@param provider_opts table
---@return string[] cmd
function M.build_cmd(provider_opts)
  local port = provider_opts.port or M.get_free_port()
  if port == 0 then
    port = M.get_free_port()
  end
  
  local cmd = { provider_opts.cmd or "opencode" }
  table.insert(cmd, "--port")
  table.insert(cmd, tostring(port))
  
  if provider_opts.args then
    for _, arg in ipairs(provider_opts.args) do
      table.insert(cmd, arg)
    end
  end
  
  return cmd
end

---Start opencode with terminal provider
function M.start_terminal()
  local opts = config.options.provider.terminal
  local cmd = M.build_cmd(opts)
  local cmd_str = table.concat(cmd, " ")
  
  vim.cmd("terminal " .. cmd_str)
  vim.cmd("startinsert")
end

---Start opencode with snacks provider
function M.start_snacks()
  local has_snacks, snacks = pcall(require, "snacks.terminal")
  if not has_snacks then
    vim.notify("snacks.nvim is not installed", vim.log.levels.ERROR)
    return
  end
  
  local opts = config.options.provider.snacks
  local cmd = M.build_cmd(opts)
  
  snacks.open({
    cmd = cmd,
    interactive = true,
  })
end

---Start opencode with kitty provider
function M.start_kitty()
  local opts = config.options.provider.kitty
  local cmd = M.build_cmd(opts)
  
  local socket_opt = ""
  if opts.socket then
    socket_opt = string.format("--to unix:%s ", opts.socket)
  end
  
  local kitty_cmd = string.format(
    "kitty %slaunch --type=window --cwd=%s %s",
    socket_opt,
    vim.fn.shellescape(vim.fn.getcwd()),
    table.concat(vim.tbl_map(vim.fn.shellescape, cmd), " ")
  )
  
  vim.fn.system(kitty_cmd)
end

---Start opencode with wezterm provider
function M.start_wezterm()
  local opts = config.options.provider.wezterm
  local cmd = M.build_cmd(opts)
  
  local wezterm_cmd = string.format(
    "wezterm cli spawn --cwd %s -- %s",
    vim.fn.shellescape(vim.fn.getcwd()),
    table.concat(vim.tbl_map(vim.fn.shellescape, cmd), " ")
  )
  
  vim.fn.system(wezterm_cmd)
end

---Start opencode with tmux provider
function M.start_tmux()
  local opts = config.options.provider.tmux
  local cmd = M.build_cmd(opts)
  
  local session_name = opts.session or "opencode"
  
  -- Check if session already exists
  local result = vim.fn.system(string.format("tmux has-session -t %s 2>/dev/null && echo 'exists' || echo 'new'", session_name))
  
  if result:match("exists") then
    -- Attach to existing session
    vim.fn.system(string.format("tmux switch-client -t %s", session_name))
  else
    -- Create new session
    local cmd_str = table.concat(vim.tbl_map(vim.fn.shellescape, cmd), " ")
    vim.fn.system(string.format(
      "tmux new-session -d -s %s -c %s %s",
      session_name,
      vim.fn.shellescape(vim.fn.getcwd()),
      cmd_str
    ))
    vim.fn.system(string.format("tmux switch-client -t %s", session_name))
  end
end

---Start opencode
function M.start()
  local provider_name = M.detect_provider()
  current_provider = provider_name
  
  if provider_name == "terminal" then
    M.start_terminal()
  elseif provider_name == "snacks" then
    M.start_snacks()
  elseif provider_name == "kitty" then
    M.start_kitty()
  elseif provider_name == "wezterm" then
    M.start_wezterm()
  elseif provider_name == "tmux" then
    M.start_tmux()
  elseif provider_name == "custom" then
    local custom_start = config.options.provider.start
    if custom_start then
      custom_start(config.options.provider)
    else
      vim.notify("Custom provider requires 'start' function", vim.log.levels.ERROR)
    end
  end
end

---Stop opencode
function M.stop()
  local client = require("opencode.client")
  local port = client.get_port()
  
  if port then
    -- Try to gracefully shutdown via API
    client.request("/shutdown", { method = "POST" })
  end
  
  -- Also try to kill the process
  vim.fn.system(string.format("pkill -f 'opencode.*--port.*%s' 2>/dev/null || true", port or ""))
  
  if current_provider == "tmux" then
    local opts = config.options.provider.tmux
    local session_name = opts.session or "opencode"
    vim.fn.system(string.format("tmux kill-session -t %s 2>/dev/null || true", session_name))
  elseif current_provider == "custom" then
    local custom_stop = config.options.provider.stop
    if custom_stop then
      custom_stop(config.options.provider)
    end
  end
end

---Toggle opencode
function M.toggle()
  local client = require("opencode.client")
  
  if client.get_port() then
    M.stop()
  else
    M.start()
  end
end

return M
