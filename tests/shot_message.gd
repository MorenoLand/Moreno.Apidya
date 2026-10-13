extends SceneTree
## Developer tool: shows the continue question of MessageScreen and saves a screenshot.
func _initialize() -> void:
	var disks: DiskSet = DiskLocator.find()["disks"]
	OsdText.set_font(disks.get_data(1))
	var m := MessageScreen.new()
	m.setup("CONTINUE", true, 3)
	root.add_child(m)
	for i in 8:
		await process_frame
	root.get_texture().get_image().save_png("G:/Development/Working/Amiga/analysis/renders/message_screen.png")
	quit(0)
