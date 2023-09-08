## Todo

- Screenshot folder in config (where the images will be kept)
- Within the Summary view, you can call the add_summary_image() command
- This command will open a UI picker to choose the file
- When you choose the file, we pass that file path to an API endpoint which uploads
the file and returns the JSON in the API here (https://docs.gitlab.com/ee/api/projects.html#upload-a-file)
- Then we write that into the Summary buffer at the current cursor
