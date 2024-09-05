package app

type PluginOptions struct {
	GitlabUrl string `json:"gitlab_url"`
	Port      int    `json:"port"`
	AuthToken string `json:"auth_token"`
	LogPath   string `json:"log_path"`
	Debug     struct {
		Request  bool `json:"go_request"`
		Response bool `json:"go_response"`
	} `json:"debug"`
	ConnectionSettings struct {
		Insecure bool   `json:"insecure"`
		Remote   string `json:"remote"`
	} `json:"connection_settings"`
}

var pluginOptions PluginOptions

func SetPluginOptions(p PluginOptions) {
	pluginOptions = p
}
