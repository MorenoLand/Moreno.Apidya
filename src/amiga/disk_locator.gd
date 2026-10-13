class_name DiskLocator
extends RefCounted
## Finds the user's Apidya disk images without any hard-coded path.
## Search order: --disks=<folder> (after "--"), APIDYA_DISKS environment variable, the folder saved by the
## start screen, <project or executable folder>/assets/original, and the executable's own folder.

static func candidates() -> Array[String]:
	var out: Array[String] = []
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--disks="):
			out.append(a.substr(8))
	var env := OS.get_environment("APIDYA_DISKS")
	if env != "":
		out.append(env)
	var saved := str(Settings.get_value("disks_path", ""))
	if saved != "":
		out.append(saved)
	out.append(ProjectSettings.globalize_path("res://assets/original"))
	var exe_dir := OS.get_executable_path().get_base_dir()
	out.append(exe_dir.path_join("assets/original"))
	out.append(exe_dir)
	return out


## Returns {disks: DiskSet or null, error: String}
static func find() -> Dictionary:
	var last_error := "No Apidya disk images found."
	for c in candidates():
		if c == "" or not DirAccess.dir_exists_absolute(c):
			continue
		var ds := DiskSet.new()
		var err := ds.load_dir(c)
		if err == "":
			return {"disks": ds, "error": ""}
		last_error = err
	return {"disks": null, "error": last_error}


static func open_folder(path: String) -> Dictionary:
	var ds := DiskSet.new()
	var err := ds.load_dir(path)
	if err == "":
		Settings.set_value("disks_path", path)
		return {"disks": ds, "error": ""}
	return {"disks": null, "error": err}
