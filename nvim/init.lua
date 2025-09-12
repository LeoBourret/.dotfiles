require("leo-bourret.core")
require("leo-bourret.lazy")
require("current-theme")

-- HACK
-- TODO
-- Find a clean way to deal with python3 packages being detected by the lsp's
vim.env.PYTHONPATH = vim.fn.getcwd() .. "/.venv/lib/python3.12/site-packages"
