local M = {}

function M.run()
  local translate = require("translate")

  translate.setup({
    persist_target = false,
    engine = "google",
    target_lang = "FA",
    default_target = "KO",
    api_key = "dummy-deepl",
    google_api_key = "dummy-google",
  })

  assert(translate.current_engine() == "google", "setup engine should be google")
  assert(translate.current_target() == "FA", "google should keep FA target")

  translate.set_engine("deepl")
  assert(translate.current_engine() == "deepl", "engine switch to deepl failed")
  assert(translate.current_target() == "KO", "unsupported target should fallback to default_target for deepl")

  translate.set_engine(" google ")
  assert(translate.current_engine() == "google", "trimmed engine switch failed")

  translate.set_target(" en-us ")
  assert(translate.current_target() == "EN", "google target normalize failed")

  translate.set_engine("deepl")
  assert(translate.current_target() == "EN-US", "deepl target normalize from EN failed")
end

return M
