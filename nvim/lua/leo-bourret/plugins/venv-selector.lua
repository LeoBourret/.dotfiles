return {
	"linux-cultist/venv-selector.nvim",
	dependencies = {
		"neovim/nvim-lspconfig",
		"nvim-telescope/telescope.nvim",
	},
	cmd = { "VenvSelect", "VenvSelectCached" }, -- 👈 dit à lazy.nvim de charger le plugin quand tu tapes ces commandes
	opts = {
		-- tu peux configurer ici si besoin
		-- par défaut il cherche .venv, venv, env, etc.
	},
	keys = {
		{ "<leader>vs", "<cmd>VenvSelect<cr>", desc = "Select VirtualEnv" },
		{ "<leader>vc", "<cmd>VenvSelectCached<cr>", desc = "Select Cached VirtualEnv" },
	},
}
