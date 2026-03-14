---@class opencode.Opts
---@field contexts? table<string, fun():string> Custom context providers
---@field prompts? table<string, string> Custom prompts
---@field provider? opencode.ProviderConfig Provider configuration
---@field ask? opencode.AskConfig Ask configuration
---@field events? opencode.EventsConfig Events configuration
---@field statusline? opencode.StatuslineConfig Statusline configuration

---@class opencode.ProviderConfig
---@field enabled? "auto"|"terminal"|"snacks"|"kitty"|"wezterm"|"tmux"|"custom" Which provider to use
---@field auto? opencode.BaseProviderConfig Auto-detect configuration
---@field terminal? opencode.TerminalProviderConfig Terminal provider configuration
---@field snacks? opencode.SnacksProviderConfig Snacks provider configuration
---@field kitty? opencode.KittyProviderConfig Kitty provider configuration
---@field wezterm? opencode.WeztermProviderConfig Wezterm provider configuration
---@field tmux? opencode.TmuxProviderConfig Tmux provider configuration
---@field toggle? fun(self) Custom provider toggle function
---@field start? fun(self) Custom provider start function
---@field stop? fun(self) Custom provider stop function

---@class opencode.BaseProviderConfig
---@field port? number Port to use for opencode server
---@field args? string[] Additional arguments to pass to opencode

---@class opencode.TerminalProviderConfig : opencode.BaseProviderConfig
---@field cmd? string Command to run opencode

---@class opencode.SnacksProviderConfig : opencode.BaseProviderConfig
---@field cmd? string Command to run opencode

---@class opencode.KittyProviderConfig : opencode.BaseProviderConfig
---@field socket? string Kitty socket path

---@class opencode.WeztermProviderConfig : opencode.BaseProviderConfig

---@class opencode.TmuxProviderConfig : opencode.BaseProviderConfig
---@field session? string Tmux session name

---@class opencode.AskConfig
---@field history_size? number Number of recent asks to remember
---@field blink_cmp_sources? boolean Register blink.cmp sources
---@field highlights? boolean Enable highlights for contexts and subagents
---@field completions? boolean Enable completions for contexts and subagents

---@class opencode.EventsConfig
---@field reload? boolean Auto-reload buffers on edit
---@field permissions? boolean Handle permission requests

---@class opencode.StatuslineConfig
---@field enabled? boolean Enable statusline component
---@field format? fun(status: opencode.Status):string Statusline format function

---@class opencode.Status
---@field connected boolean Whether connected to opencode
---@field busy boolean Whether opencode is busy
---@field port? number The port opencode is running on

local M = {}

---@type opencode.Opts
M.defaults = {
  contexts = {},
  prompts = {
    diagnostics = "Explain @diagnostics",
    diff = "Review the following git diff for correctness and readability: @diff",
    document = "Add comments documenting @this",
    explain = "Explain @this and its context",
    fix = "Fix @diagnostics",
    implement = "Implement @this",
    optimize = "Optimize @this for performance and readability",
    review = "Review @this for correctness and readability",
    test = "Add tests for @this",
  },
  provider = {
    enabled = "auto",
    auto = {
      port = 0,
      args = {},
    },
    terminal = {
      port = 0,
      args = {},
      cmd = "opencode",
    },
    snacks = {
      port = 0,
      args = {},
      cmd = "opencode",
    },
    kitty = {
      port = 0,
      args = {},
      socket = nil,
    },
    wezterm = {
      port = 0,
      args = {},
    },
    tmux = {
      port = 0,
      args = {},
      session = nil,
    },
  },
  ask = {
    history_size = 50,
    blink_cmp_sources = true,
    highlights = true,
    completions = true,
  },
  events = {
    reload = true,
    permissions = true,
  },
  statusline = {
    enabled = true,
    format = function(status)
      if not status.connected then
        return "󰚩 "
      elseif status.busy then
        return "󰚩 ..."
      else
        return "󰚩 "
      end
    end,
  },
}

---@type opencode.Opts
M.options = {}

---@param opts? opencode.Opts
function M.setup(opts)
  M.options = vim.tbl_deep_extend("force", {}, M.defaults, opts or {})
end

return M
