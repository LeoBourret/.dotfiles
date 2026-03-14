local config = require("opencode.config")
local provider = require("opencode.provider")

---@class opencode.cli.client.Event
---@field type string Event type
---@field data? any Event data

---@class opencode.Status
---@field connected boolean
---@field busy boolean
---@field port? number

local M = {}

local status = {
  connected = false,
  busy = false,
  port = nil,
}

local event_poll_timer = nil

---Get the current status
---@return opencode.Status
function M.get_status()
  return vim.deepcopy(status)
end

---Detect if opencode is running on a port
---@return number? port The port opencode is running on, or nil if not found
function M.detect_port()
  -- Check environment variable first
  local env_port = vim.env.OPENCODE_PORT
  if env_port then
    local port = tonumber(env_port)
    if port and M.check_port(port) then
      return port
    end
  end
  
  -- Scan common ports
  for port = 3000, 3010 do
    if M.check_port(port) then
      return port
    end
  end
  
  return nil
end

---Check if opencode is running on a specific port
---@param port number
---@return boolean
function M.check_port(port)
  local handle = io.popen(string.format("curl -s -o /dev/null -w '%%{http_code}' http://localhost:%d/health 2>/dev/null || echo '000'", port))
  if not handle then
    return false
  end
  
  local result = handle:read("*a")
  handle:close()
  
  return result:match("200") ~= nil
end

---Get the current port, auto-detecting if necessary
---@return number? port
function M.get_port()
  if status.port and M.check_port(status.port) then
    return status.port
  end
  
  local port = M.detect_port()
  if port then
    status.port = port
    status.connected = true
    return port
  end
  
  return nil
end

---Make a request to the opencode server
---@param endpoint string
---@param opts? { method?: string, body?: table }
---@return table? response
function M.request(endpoint, opts)
  opts = opts or {}
  local port = M.get_port()
  
  if not port then
    vim.notify("opencode is not running", vim.log.levels.WARN)
    return nil
  end
  
  local url = string.format("http://localhost:%d%s", port, endpoint)
  local cmd = { "curl", "-s", "-X", opts.method or "GET" }
  
  if opts.body then
    table.insert(cmd, "-H")
    table.insert(cmd, "Content-Type: application/json")
    table.insert(cmd, "-d")
    table.insert(cmd, vim.json.encode(opts.body))
  end
  
  table.insert(cmd, url)
  
  local handle = io.popen(table.concat(cmd, " ") .. " 2>/dev/null")
  if not handle then
    return nil
  end
  
  local result = handle:read("*a")
  handle:close()
  
  if result == "" then
    return nil
  end
  
  local ok, decoded = pcall(vim.json.decode, result)
  if ok then
    return decoded
  end
  
  return nil
end

---Send a prompt to opencode
---@param prompt string
function M.send_prompt(prompt)
  local response = M.request("/prompt", {
    method = "POST",
    body = { prompt = prompt },
  })
  
  if response then
    status.busy = true
  end
end

---Send a command to opencode
---@param command string
function M.send_command(command)
  local response = M.request("/command", {
    method = "POST",
    body = { command = command },
  })
  
  if response then
    -- Some commands change busy state
    if command:match("^session%.") then
      status.busy = true
    end
  end
end

---Send permission response
---@param id string
---@param approved boolean
function M.send_permission_response(id, approved)
  M.request("/permission", {
    method = "POST",
    body = {
      id = id,
      approved = approved,
    },
  })
end

---Poll for events from opencode
function M.poll_events()
  local port = M.get_port()
  if not port then
    return
  end
  
  local url = string.format("http://localhost:%d/events", port)
  local handle = io.popen(string.format("curl -s -N --max-time 1 %s 2>/dev/null || true", url))
  if not handle then
    return
  end
  
  -- Read events
  local data = handle:read("*a")
  handle:close()
  
  if data and data ~= "" then
    -- Parse SSE format
    for line in data:gmatch("data: ([^\n]+)") do
      local ok, event = pcall(vim.json.decode, line)
      if ok and event then
        M.handle_event(event, port)
      end
    end
  end
end

---Handle an event from opencode
---@param event table
---@param port number
function M.handle_event(event, port)
  -- Update busy status based on event type
  if event.type == "session.idle" then
    status.busy = false
  elseif event.type == "session.message" or event.type == "session.thinking" then
    status.busy = true
  end
  
  -- Emit autocmd
  vim.schedule(function()
    vim.api.nvim_exec_autocmds("User", {
      pattern = "OpencodeEvent:*",
      data = {
        event = event,
        port = port,
      },
    })
    
    -- Also emit specific event pattern
    vim.api.nvim_exec_autocmds("User", {
      pattern = "OpencodeEvent:" .. event.type,
      data = {
        event = event,
        port = port,
      },
    })
  end)
end

---Start polling for events
function M.start_polling()
  if event_poll_timer then
    return
  end
  
  event_poll_timer = vim.loop.new_timer()
  event_poll_timer:start(0, 1000, vim.schedule_wrap(function()
    M.poll_events()
  end))
end

---Stop polling for events
function M.stop_polling()
  if event_poll_timer then
    event_poll_timer:stop()
    event_poll_timer:close()
    event_poll_timer = nil
  end
end

return M
