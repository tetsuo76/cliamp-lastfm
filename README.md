![scrobbling in cliamp](https://github.com/tetsuo76/cliamp-lastfm/blob/main/screenshot.png?raw=true)

Simple last.fm plugin v1.3.0 for [cliamp](https://github.com/bjarneo/cliamp)

Info about last.fm authentication (in order to create your API_KEY and API_SECRET):
https://www.last.fm/api/authentication

Useful python app to obtain your SESSION_KEY:
https://github.com/TheMemoman/lastfm_Get_Session_Key

Installation/Config:

- Copy the plugin (lastfm.lua) into the cliamp's plugins directory (`~/.config/cliamp/plugins`). 

- Edit cliamp's config file (`~/.config/cliamp/config.toml`) and add the required last.fm section:

```
[plugins.lastfm]
api_key = "API_KEY"
api_secret = "API_SECRET"
session_key = "SESSION_KEY"
username = "LASTFM_USERNAME"
```

- Replace API_KEY, API_SECRET, SESSION_KEY and LASTFM_USERNAME username with your own.

Tested with cliamp v1.39.0
