package app

type PluginOptions struct {
	GitlabUrl string `json:"gitlab_url"`
	Port      int    `json:"port"`
	AuthToken string `json:"auth_token"`
	LogPath   string `json:"log_path"`
	Debug     struct {
		Request        bool `json:"request"`
		Response       bool `json:"response"`
		GitlabRequest  bool `json:"gitlab_request"`
		GitlabResponse bool `json:"gitlab_response"`
	} `json:"debug"`
	ChosenMrIID        int `json:"chosen_mr_iid"`
	ConnectionSettings struct {
		Insecure bool   `json:"insecure"`
		Remote   string `json:"remote"`
	} `json:"connection_settings"`
}

var pluginOptions PluginOptions

func SetPluginOptions(p PluginOptions) {
	pluginOptions = p
}
