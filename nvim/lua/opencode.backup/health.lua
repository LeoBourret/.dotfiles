local M = {}

function M.check()
  vim.health.start("opencode.nvim")
  
  -- Check for opencode CLI
  local opencode_path = vim.fn.executable("opencode")
  if opencode_path == 1 then
    vim.health.ok("opencode CLI is installed")
  else
    vim.health.error("opencode CLI is not installed or not in PATH")
    vim.health.info("Install opencode from: https://github.com/sst/opencode")
  end
  
  -- Check for optional dependencies
  local has_snacks, _ = pcall(require, "snacks")
  if has_snacks then
    vim.health.ok("snacks.nvim is installed (optional)")
  else
    vim.health.warn("snacks.nvim is not installed (optional, recommended)")
  end
  
  -- Check provider availability
  local config = require("opencode.config")
  local provider_name = config.options.provider.enabled
  
  if provider_name == "auto" or provider_name == "kitty" then
    if vim.fn.executable("kitty") == 1 then
      vim.health.ok("kitty is installed")
    elseif provider_name == "kitty" then
      vim.health.error("kitty is not installed but configured as provider")
    end
  end
  
  if provider_name == "auto" or provider_name == "wezterm" then
    if vim.fn.executable("wezterm") == 1 then
      vim.health.ok("wezterm is installed")
    elseif provider_name == "wezterm" then
      vim.health.error("wezterm is not installed but configured as provider")
    end
  end
  
  if provider_name == "auto" or provider_name == "tmux" then
    if vim.fn.executable("tmux") == 1 then
      vim.health.ok("tmux is installed")
    elseif provider_name == "tmux" then
      vim.health.error("tmux is not installed but configured as provider")
    end
    
    if vim.env.TMUX then
      vim.health.ok("Running inside tmux session")
    elseif provider_name == "tmux" then
      vim.health.warn("Not running inside a tmux session")
    end
  end
  
  -- Check connection to opencode
  local client = require("opencode.client")
  local port = client.detect_port()
  
  if port then
    vim.health.ok(string.format("Connected to opencode on port %d", port))
  else
    vim.health.warn("opencode is not currently running (will auto-start on first use)")
  end
  
  -- Check autoread setting
  if vim.o.autoread then
    vim.health.ok("autoread is enabled (required for file reload)")
  else
    vim.health.warn("autoread is not enabled — add `vim.o.autoread = true` to your config")
  end
end

return M
